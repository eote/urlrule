#!/usr/bin/perl -w
package MyPlace::URLRule;
use URI;
use URI::Escape;
use MyPlace::Script::Message;
#use Term::ANSIColor;
use MyPlace::Curl;
use strict;
use Cwd;

BEGIN {
    use Exporter ();
    our ($VERSION,@ISA,@EXPORT,@EXPORT_OK,%EXPORT_TAGS);
    $VERSION        = 1.00;
    @ISA            = qw(Exporter);
    @EXPORT_OK         = qw($URLRULE_DIRECTORY &parse_rule &apply_rule &get_domain &get_rule_dir set_callback);
}

#my $URLRULE_DIRECTORY = "$ENV{XR_PERL_SOURCE_DIR}/urlrule";

our $USER_URLRULE_DIRECTORY = "$ENV{HOME}/.urlrule";
our $URLRULE_DIRECTORY = "$ENV{XR_PERL_SOURCE_DIR}/urlrule";

unshift @INC,$URLRULE_DIRECTORY;
unshift @INC,$USER_URLRULE_DIRECTORY;
my %CALLBACK;
sub unescape_text {
    my %ESCAPE_MAP = (
        "&lt;","<" ,"&gt;",">",
        "&amp;","&" ,"&quot;","\"",
        "&agrave;","à" ,"&Agrave;","À",
        "&acirc;","â" ,"&auml;","ä",
        "&Auml;","Ä" ,"&Acirc;","Â",
        "&aring;","å" ,"&Aring;","Å",
        "&aelig;","æ" ,"&AElig;","Æ" ,
        "&ccedil;","ç" ,"&Ccedil;","Ç",
        "&eacute;","é" ,"&Eacute;","É" ,
        "&egrave;","è" ,"&Egrave;","È",
        "&ecirc;","ê" ,"&Ecirc;","Ê",
        "&euml;","ë" ,"&Euml;","Ë",
        "&iuml;","ï" ,"&Iuml;","Ï",
        "&ocirc;","ô" ,"&Ocirc;","Ô",
        "&ouml;","ö" ,"&Ouml;","Ö",
        "&oslash;","ø" ,"&Oslash;","Ø",
        "&szlig;","ß" ,"&ugrave;","ù",
        "&Ugrave;","Ù" ,"&ucirc;","û",
        "&Ucirc;","Û" ,"&uuml;","ü",
        "&Uuml;","Ü" ,"&nbsp;"," ",
        "&copy;","\x{00a9}",
        "&reg;","\x{00ae}",
        "&euro;","\x{20a0}",
    );
    my $text = shift;
    return unless($text);
    foreach (keys %ESCAPE_MAP) {
        $text =~ s/$_/$ESCAPE_MAP{$_}/g;
    }
    $text =~ s/&#(\d+);/chr($1)/eg;
    $text = uri_unescape($text);
#    $text =~ s/[_-]+/ /g;
    $text =~ s/[\:]+/, /g;
    $text =~ s/[\\\<\>"\^\&\*\?]+//g;
    $text =~ s/\s{2,}/ /g;
    $text =~ s/(?:^\s+|\s+$)//;
    return $text;
}

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
            use Cwd 'abs_path';
            $r{"local_path"} = abs_path($1);
        }
    }
    if($r{url} !~ /^http:\/\//i) {
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
        for my $directory (
            "$USER_URLRULE_DIRECTORY/$r{level}",
            "$USER_URLRULE_DIRECTORY/common",
            "$URLRULE_DIRECTORY/$r{level}",
            "$URLRULE_DIRECTORY/common",
            )
        {
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
    $r{source} 
        = "$USER_URLRULE_DIRECTORY/$r{level}/$r{domain}" unless($r{source});
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
	my $tempname = "$url\:\:$level";
	$tempname =~ s/^[^:]+\:|&.+$|\?.+$|#.+$//g;
	$tempname =~ s/[\.\/\\]/::/g;
	$tempname =~ s/^\:+//g;
eval<<"CODE";
	package $tempname;
	no warnings;
	no strict qw/subs/;
    do \$source;
CODE
    package MyPlace::URLRule;
    #if($@) {
    #    return undef,"Couldn't parse ",'RED',$source,"\n$@";
    #}
    my @result = eval $tempname . '::apply_rule($url,$rule);';
    return undef,'Nothing to do' unless(@result);
	return undef,'Nothing to do'  unless($result[0]);
    my %result = @result;
    if($result{"#use quick parse"}) {
        %result = urlrule_quick_parse('url'=>$url,%result);
    }
	$result{rule} = $rule;
    return 1,\%result;
}

sub urlrule_quick_parse {
    my %args = @_;
    my $url = $args{url};
    die("Error 'url=>undef'\n") unless($url);
    my $title;
#    my %rule = %{$args{rule}};
    my ($title_exp,$title_map,$data_exp,$data_map,$pass_exp,$pass_map,$pass_name_exp,$pass_name_map,$pages_exp,$pages_map,$pages_pre,$pages_suf,$pages_start,$charset) = @args{qw/
        title_exp
        title_map
        data_exp
        data_map
        pass_exp
        pass_map
        pass_name_exp
        pass_name_map
        pages_exp
        pages_map
        pages_pre
        pages_suf
        pages_start
        charset
    /};
    my $http = MyPlace::Curl->new();
    my (undef,$html) = $http->get($url,(defined $charset ? "charset:$charset" : undef),'--referer',$url);
    my @data;
    my @pass_data;
    my @pass_name;
	my %h_data;
	my %h_pass;
    $data_map = '$1' unless($data_map);
    $pass_map = '$1' unless($pass_map);
	my %LOCAL_VAR;
    $pass_name_map = $pass_name_exp unless($pass_name_map);
    if($title_exp) {
        $title_map = '$1' unless($title_map);
        if($html =~ m/$title_exp/g) {
            $title = eval $title_map;
        }
    }
    if($data_exp) {
        while($html =~ m/$data_exp/g) {
			my $r = eval $data_map;
			next unless($r);
			next if($h_data{$r});
            push @data,$r;
			$h_data{$r} = 1;
        }
    }
    if($pass_exp) {
        while($html =~ m/$pass_exp/g) {
            my $r = eval $pass_map;
			next if($h_pass{$r});
            push @pass_data,$r;
			$h_pass{$r} = 1;
            push @pass_name,eval $pass_name_map if($pass_name_map);
        }
    }
    elsif($pages_exp) {
        $pages_start = 2 unless(defined $pages_start);
        my $last = $pages_start - 1; 
        my $pre = "";
        my $suf = "";
        while($html =~ m/$pages_exp/g) {
            if(eval($pages_map) > $last) {
                    $last = eval $pages_map;
                    $pre = eval $pages_pre  if($pages_pre);
                    $suf = eval $pages_suf if($pages_suf);
            }
        }
        if($last >= $pages_start) {
            @pass_data = map "$pre$_$suf",($pages_start .. $last);
        }
        push @pass_data,$url;
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


