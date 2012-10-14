#!/usr/bin/perl -w
package MyPlace::URLRule;
use URI;
use URI::Escape;
use MyPlace::Script::Message;
use MyPlace::URLRule::Utils qw/&get_url &parse_pages/;
use Cwd qw/abs_path getcwd/;
use strict;

BEGIN {
    use Exporter ();
    our ($VERSION,@ISA,@EXPORT,@EXPORT_OK,%EXPORT_TAGS);
    $VERSION        = 1.00;
    @ISA            = qw(Exporter);
	@EXPORT			=	qw/&parse_rule &apply_rule &set_callback/;
    @EXPORT_OK         = qw(@URLRULE_LIB $URLRULE_DIRECTORY &parse_rule &apply_rule &get_domain &get_rule_dir set_callback);
}

#my $URLRULE_DIRECTORY = "$ENV{XR_PERL_SOURCE_DIR}/urlrule";

our $USER_URLRULE_DIRECTORY = "$ENV{HOME}/.urlrule";
our $URLRULE_DIRECTORY = "$ENV{XR_PERL_SOURCE_DIR}/urlrule";
our @URLRULE_LIB = (getcwd . "/urlrule",$USER_URLRULE_DIRECTORY,$URLRULE_DIRECTORY);


unshift @INC,@URLRULE_LIB;
my %CALLBACK;

sub get_rule_dir() {
    return $URLRULE_DIRECTORY;
}
sub get_domain($) {
    my $url = shift;
	$url =~ s/^.*?:\/+//g;
	$url =~ s/\/.*//g;
	return $url;
    if($url =~ /([^\.\/]+\.[^\.\/]+)\//) {
        return $1;
    }
    elsif($url =~ /^([^\.\/]+\.[^\.\/]+)$/) {
        return $1;
    }
    else {
        return $url;
    }
}
sub new_rule {
	return parse_rule(@_);
}
sub parse_rule {
    my %r;
    $r{url} = shift;
    if($r{url} =~ /^local:([^\/]+)/) {
        $r{"local"} = $1;
        $r{url} =~ s/^local:/file_/;
        if($r{url} =~ /^file_[^\/]+\/(.*)$/) {
            $r{"local_path"} = abs_path($1);
        }
    }
    if($r{url} !~ /^https?:\/\//i) {
        $r{url} = "http://" . $r{url};
    }
    $r{level} = shift;
    if($r{level} and $r{level} =~ /^domain:(.*)$/) {
        $r{domain} = $1;
        $r{level} = shift;
    }
    $r{domain} = get_domain($r{url}) unless($r{domain});

    if($r{level}) {
       if($r{level} !~ /^\d+$/) {
        unshift @_,$r{level};
        $r{level} = 0;
       }
    }
    else {
        $r{level} = 0;
    }
    $r{action} = shift;
    $r{action} = "" unless($r{action});
    @{$r{args}} = @_;
    my $domain = $r{domain};
    do 
    {
        foreach my $directory (
			map {("$_/$r{level}","$_/common")} @URLRULE_LIB
		){
#			print STDERR "Try $directory - $domain\n";
            next unless(-d $directory);
            for my $basename 
                    (
                        $domain,
                        "${domain}.pl",
                        "www.$domain",
                        "www.${domain}.pl",
                    )

            {
                if(-f "$directory/$basename") 
                {
                    $r{source} = "$directory/$basename";
                    last;
                }
            }
            last if($r{source});
        }
    } while($domain =~ s/^[^\.]*\.// and !$r{source});
	if(!$r{source}) {
		foreach(@URLRULE_LIB) {
			if(-d $_) {
				$r{source} = "$_/$r{level}/$r{domain}";
				last;
			}
		}
	}
    $r{source} 
        = "urlrule/$r{level}/$r{domain}" unless($r{source});
    return \%r;
}

sub get_passdown {
	my $result = shift;

}

sub set_callback {
	my $name = shift;
	$CALLBACK{$name} = [@_];
}

sub callback_apply_rule {
	if(!$CALLBACK{'apply_rule'}) {
		print STDERR "Callback \"apply_rule\" not definied\n";
	}
	else {
		my @callback = @{$CALLBACK{apply_rule}};
		my $func = shift @callback;
		&$func(@_,@callback);
	}
}

sub apply_rule {
    my $rule = shift;
    unless($rule and ref $rule and %{$rule}) {
        return undef,"Invalid rule, could not apply!";
    }
    my $level = $rule->{level};
    my $url = $rule->{url};
    my $source = $rule->{"source"};
    unless(-f $source) {
		return undef,"File not found: $source";
    }
	
	no warnings 'redefine';
	package MyPlace::URLRule::Rule;
	no warnings 'redefine';
	do $source;

	print STDERR "$@\n" if($@);
	$@ = undef;

	foreach(qw(@URLRULE_LIB $URLRULE_DIRECTORY &parse_rule &get_domain &get_rule_dir set_callback callback_apply_rule)) {
		${MyPlace::URLRule::Rule::}{"$_"} = ${MyPlace::URLRule::}{"$_"};
	}
	
	use warnings;
    package MyPlace::URLRule;
	use warnings;
    my ($status,@result) = MyPlace::URLRule::Rule::apply_rule($url,$rule);
    return undef,'Nothing to do' unless($status);
    my %result = ($status,@result);
    if($result{"#use quick parse"}) {
        %result = urlrule_quick_parse('url'=>$url,%result);
    }
	$result{rule} = $rule;
    return 1,\%result;
}

sub urlrule_quick_parse {
    my %args = @_;
    my $url = $args{url};;

    die("Error 'url=>undef'\n") unless($url);
    my $title;
#    my %rule = %{$args{rule}};
    my ($title_exp,$title_map,
		$data_exp,$data_map,
		$pass_exp,$pass_map,$pass_name_exp,$pass_name_map,
		$pages_exp,$pages_map,$pages_pre,$pages_suf,$pages_start,$pages_margin,
		$charset) = @args{qw/
        title_exp title_map
        data_exp data_map
		pass_exp pass_map pass_name_exp pass_name_map 
        pages_exp pages_map pages_pre pages_suf pages_start pages_margin
        charset
    /};
    my $html = get_url($url,'-v',(defined $charset ? "charset:$charset" : undef),'referer'=>$url);
    my @data;
    my @pass_data;
    my @pass_name;
	my %h_data;
	my %h_pass;
    $data_map = '$1' unless($data_map);
    $pass_map = '$1' unless($pass_map);
	my %LOCAL_VAR;
    $pass_name_map = $pass_name_exp unless($pass_name_map);
    if($data_exp) {
        while($html =~ m/$data_exp/og) {
			my $r = eval $data_map;
			#print STDERR "$data_exp => $data_map => $r\n";
			next unless($r);
			next if($h_data{$r});
            push @data,$r;
			$h_data{$r} = 1;
        }
    }
    if($pass_exp) {
        while($html =~ m/$pass_exp/og) {
            my $r = eval $pass_map;
			next if($h_pass{$r});
            push @pass_data,$r;
			$h_pass{$r} = 1;
            push @pass_name,eval $pass_name_map if($pass_name_map);
        }
    }
    elsif($pages_exp) {
		my $pages =  &parse_pages(
				source=>$url,
				data=>$html,
				exp=>$pages_exp,
				map=>$pages_map,
				prefix=>$pages_pre,
				suffix=>$pages_suf,
				start=>$pages_start,
				margin=>$pages_margin,
		);
		if(!@pass_data) {
			@pass_data = @{$pages};
		}
		else {
			push @pass_data,@{$pages};
		}
    }
    if($title_exp) {
        $title_map = '$1' unless($title_map);
        if($html =~ m/$title_exp/) {
            $title = eval $title_map;
        }
    }
#	use Data::Dumper;die(Dumper(\%h_pass));
#    @data = delete_dup(@data) if(@data);
#    @pass_data = delete_dup(@pass_data) if(@pass_data and (!@pass_name));
    return (
        count=>scalar(@data),
        data=>[@data],
        pass_count=>scalar(@pass_data),
        pass_data=>[@pass_data],
        pass_name=>[@pass_name],
        base=>$url,
        no_subdir=>(@pass_name ? 0 : 1),
        work_dir=>$title,
        %args,
    );
}

1;

__END__

=pod

=head1  NAME

MyPlace::URLRule - Common routines form urlrule

=head1  SYNOPSIS

    use MyPlace::URLRule;

    sub process_rule
    {
        my ($status1,$rule,$result) 
            = urlrule_process_args(@_);
        if($status1) {
            my ($status2,$pass_count,@pass_args) 
                = urlrule_process_result($rule,$result);
            if($status2 and $pass_count>0) 
            {
                foreach my $args_ref (@pass_args) {
                    process_rule(@{$_});
                }
            }
        }
    }
    process_rule(undef,@ARGV);
        
=head1 DESCRIPTION

Common rountines for urlrule_action urlrule_task ...

=head1  CHANGELOG

    2010-06-12  xiaoranzzz  <xiaoranzzz@myplace.hell>
        
        * add POD document
        * add function perform_action()
        * add $URLRULE_DIRECTORY/common for rules not differ in level.

=head1  AUTHOR

xiaoranzzz <xiaoranzzz@myplace.hell>

=cut


