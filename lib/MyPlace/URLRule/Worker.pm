#!/usr/bin/perl -w
package MyPlace::URLRule::Worker;
our $VERSION = 'v2.0';

use MyPlace::URLRule qw/parse_rule @URLRULE_LIB get_rule_handler/;
 
use strict;
use warnings;
use Cwd qw//;
use MyPlace::Script::Message;
use File::Basename;
use MyPlace::Program::Saveurl;
#use Encode qw/decode_utf8 encode_utf8 find_encoding/;
use utf8;
#my $UTF8 = find_encoding("utf-8");
my $PROGRAM_SAVE;

sub getcwd {
	goto &Cwd::getcwd;
	#return $UTF8->decode(Cwd::getcwd());
}

sub lib {
	my $self = shift;
	if(@_) {
		@URLRULE_LIB = @_;
	}
	else {
		return \@URLRULE_LIB;
	}
}

sub short_wd {
	my $full = shift;
	my $base = shift;
	$base =~ s/[^\/]+$//;
	if($base) {
		return substr($full,length($base));
	}
	else {
		return $full;
	}
}

sub new {
	my $class = shift;
	my %res = @_;
	my $self = {};
	$self->{request} = {
			buildurl=>1,
			createdir=>1,
			%res
		};
	if($self->{request}->{buildurl}) {
		require URI;
	}
	$self->{startwd} = getcwd();
	$self = bless $self,$class;
	#MyPlace::URLRule::set_callback(
	#	'apply_rule',
	#	\&callback_applyRule,
	#	$self
	#);
	return $self;
}

sub _safe_path {
	foreach(@_) {
		next unless($_);
		s/^\.+//g;
		s/:/ - /g;
		#s/[\/\\\?\*]/_/g;
		s/^\s+|[\.\s]+$|(?<=\/)\s+|[\.\s]+(?=\/)//g;
		s/\s+/ /g;
	}
	if(wantarray) {
		return @_;
	}
	else {
		return $_[0] if($_[0]);
	}
}
sub changedir {
	my $self = shift;
	my $dir = shift;
	#my $msg = shift(@_) || "";
	#$msg = "($msg)" if($msg);
	#app_prompt($self->{msghd} . "$msg" . "Changes directory","$dir\n");
	app_prompt($self->{msghd} . "Changes directory","$dir\n");
	chdir($dir);
}
sub makedir {
	my $self = shift;
	my $dir = shift;
	#print STDERR "DIR:$dir\n";
	my $pdir = dirname($dir);
	#print STDERR "PDIR:$pdir\n";
	if($pdir and (! -d $pdir)) {
		$self->makedir($pdir);
	}
	return if(-d $dir);
	app_prompt($self->{msghd} . 'Creates directory',$dir,"\n");
	mkdir($dir);
}
sub outdated {
	my $self = shift;
	$self->{outdated} = 1;
	app_warning($self->{msghd} . 'STOP HERE DATA IS OUTDATED',"\n");
	return;
}

sub _return {
	my $self = shift;
	my $return = shift;
	my $dir = shift;
	my $msghd = shift;
	if($dir) {
		chdir $dir or app_error("Error entering directory <$dir>: $!\n");
	}
	if(defined $msghd) {
		$self->{msghd} = $msghd;
	}
	return $return;
}


sub callback_applyRule {
	my($from,$rule,$result,$self) = @_;
	my $response = $self->to_response($result,$rule);
	#app_prompt($self->{msghd} . 'applyRule callback',$from,"\n\n");
	if($self->{request}->{process_callback_applyrule} || $self->{request}->{callback_process}) {
		my $cwd = getcwd;
		@_ = ($self,$response,$rule);
		$self->process($response,$rule);
		chdir($cwd);
	}
	else {
		push @{$self->{response}},$response;
		$self->{callback_called} = 1;
	}
}


sub new_request {
	my $self = shift;
	my $request = shift;
	if(!ref $request) {
		unshift @_,$request;
		$request = {};
		@{$request}{qw/url level action title progress/} = @_;
	}
	$request = {%{$self->{request}},%{$request}};
	$request->{action} = 'COMMAND:echo' unless($request->{action});
	return $request;
}

sub get_rule {
	my $self = shift;
	my $request = shift;
	my $rule = parse_rule(@{$request}{qw/url level action/});
	return $rule;
}


sub apply_rule {
	my ($self,$rule,$request) = @_;
	my $handler = get_rule_handler($rule);
	if(!$handler) {
		return 0,{error=>"No handler found for " . $rule->{url}};
	}
	if($self->{request}->{BeforeApplyRule}) {
		$self->{request}->{BeforeApplyRule}($rule,$request,$handler);
	}
	my ($status,$result) = $handler->apply($request->{url},$request->{level},$request->{action});
	if($self->{request}->{AfterApplyRule}) {
		($status,$result) = $self->{request}->{AfterApplyRule}($status,$result,$rule,$request,$handler);
	}
	return $status,$result;
}

sub process {
	my $self = shift;
	my $res = $self->new_request(@_);
	my $rule = $self->get_rule($res);
	$self->{rule} = $rule;
	$self->{request} = $res;
	if(!$self->{urls}) {
		$self->{urls} = [];
	}
	push @{$self->{urls}},$res->{url};
	return $self->process_request($rule,$res);
}

sub process_request {
	my $self = shift;
	my $rule = shift;
	my $res = shift;

	$self->{msghd} = ($res->{progress} || '') . "[L$rule->{level}] ";
	$self->{response} = undef;
	$self->{callback_called} = undef;
	my $DIR_KEEP = getcwd;
	app_prompt($self->{msghd} . 'Rule',$rule->{source},"\n");
	if($self->{request}->{createdir} && $res->{title}) {
		my $wd = _safe_path($res->{title});
		if(! -d $wd) {
			$self->makedir($wd) or die("$!\n");
		}
		$self->changedir($wd,'Request') or die("$!\n");
	}
	app_prompt($self->{msghd} . 'URL' , $rule->{url},"\n");
    app_prompt($self->{msghd} . "Directory",short_wd($DIR_KEEP,$self->{startwd}),"\n");
	my ($status,$result) = $self->apply_rule($rule,$res);
	
	my @responses;
	if($self->{callback_called}) {
		@responses = @{$self->{response}};
		$self->{callback_called} = undef;
		$self->{response} = undef;
	}
	elsif(!$status) {
		if($result->{error}) {
			app_error($self->{msghd},"Error: $result->{error}","\n");
		}
		elsif($result->{message}) {
			app_message($self->{msghd},$result->{message},"\n");
		}
		else {
			app_error($self->{msghd},"Unknown error accoure\n");
		}
	}
	elsif($result->{failed}) {
		app_error($self->{msghd},"Rule not working for $res->{url}\n");
	}
	push @responses,$result;# if($status);
	foreach my $response (@responses) {
		if($self->{outdated}) {
			return $self->_return(2,$DIR_KEEP,"");
		}
		$self->process_result($response,$rule,$res);
		if($self->{outdated}) {
			return $self->_return(2,$DIR_KEEP,"");
		}
		$self->process_nextlevel($response,$rule,$res);
		$self->{msghd} = "[Level $rule->{level}] ";
		chdir $DIR_KEEP;
	}
	return $self->_return($status,$DIR_KEEP,"");
	return $self->_return(1,$DIR_KEEP,"");
}


sub process_nextlevel {
	my $self = shift;
	my $response = shift;
	my $rule = shift;
	my $request = shift;

		if($response->{nextlevel}) {
			my %next = %{$response->{nextlevel}};
			app_prompt($self->{msghd} . 'NextLevel','Get ' . $next{count} . " items\n");# if($next{level});
			$self->{msghd} = "[Level $next{level}] ";
			if($response->{base} and $self->{request}->{buildurl}) {
				foreach(@{$next{data}}) {
					#print STDERR $_,"\n";
					if(m/^(.+)\s*\t\s*([^\t]+)$/) {
						$_ = URI->new_abs($1,$response->{base})->as_string . "\t$2"
					}
					else {
						$_ = URI->new_abs($_,$response->{base})->as_string;
					}	
				}
			}
			my $cwd = getcwd;
			my $count = $next{count};
			my $idx = $count;
			foreach my $link (@{$next{data}}) {
				my $linkname = undef;
				if($link =~ m/^(.+)\s*\t\s*([^\t]+)$/) {
					$link = $1;
					$linkname = $2;
				}
				my $req = {
					level=>$next{level},
					action=>$next{action},
					progress=>($request->{progress} || "") . "[$idx/$count]",
					url=>$link,
					title=>$linkname,
				};
				$idx--;
				$self->process($req);
				return if($self->{outdated});
				chdir($cwd);
			}
		}
}

sub process_result {
	my $self = shift;
	my $response = shift;
	my $rule = shift;
	if($self->{request}->{callback_process}) {
		app_prompt($self->{msghd},"Get " . $response->{count} . " items\n") if($response->{count});
		unshift @_,$self,$response,$rule;
		goto $self->{request}->{callback_process};
	}
	my $wd;
	if($self->{request}->{createdir}) {
		my $wd = _safe_path($response->{title});
		if($wd) {
			if(! -d $wd) {
				$self->makedir($wd) or die("$!\n");
			}
			$self->changedir($wd,'process') or die("$!\n");
		}
	}
#	if(!$response->{count}) {
#		app_prompt($self->{msghd}, "Nothing to process" . ($response->{title} ? " for [$response->{title}]\n" : "\n" ));
#		return $response->{data};
#	}
	app_prompt($self->{msghd},"Get " . $response->{count} . " items\n") if($response->{count});
#	return unless($response->{count}>0);
	if($response->{base} and $self->{request}->{buildurl}) {
		foreach(@{$response->{data}}) {
			if($_ =~ m/^([^\t]+)\t+(.+)$/) {
				$_ = URI->new_abs($1,$response->{base})->as_string() . "\t$2";
			}
			else {
				$_ = URI->new_abs($_,$response->{base})->as_string; 
			}
		}
	}
	if($self->{request}->{callback_action}) {
		return $self->{request}->{callback_action}($self,$response->{data},$response,$rule);
	}
	$self->perform_action($response->{data},$response,$rule);
	return $response->{data};
}

sub perform_action {
	my $self = shift;
	my $data = shift;
	my $response = shift;
	my $rule = shift;
    return undef,"No data" unless($data);
    if(ref $data eq 'SCALAR') {
		$data = [$data];
    }
	my $action = $response->{pipeto} || $response->{action} || '';
    app_prompt($self->{msghd} . "Directory",short_wd(getcwd,$self->{startwd}),"\n");
    if($action eq 'DUMP') {
        use Data::Dumper;
        local $Data::Dumper::Purity = 1; 
        print Data::Dumper->Dump([$response],qw/*response/);
		return;
    }

	if(!@{$data}) {
		app_prompt($self->{msghd},colored("No data\n",'RED'));
		return undef, 'No data';
	}


	if(!$self->{datas}) {
		$self->{datas} = [];
	}
	push @{$self->{datas}},@$data;

	my $base = $response->{base} || $rule->{base} || $rule->{url};
    my $file=$response->{file};
    $file =~ s/\s*\w*[\/\\]\w*\s*//g if($file);
#    print Data::Dumper->Dump([$response],qw/*response/);
	{
		$action =~ s/#URLRULE_BASE#/$base/g;
		$action =~ s/#URLRULE_TITLE#/$response->{title}/g;
	}
    if($file) {
		app_prompt($self->{msghd} . 'Writes file',$file);
        if (-f $file) {
			print STDERR colored('RED',"Ingored (File exists)...\n");
			return undef;
        }
        else {
            open FO,">:utf8",$file or die("$!\n");
            print FO @{$data};
            close FO;
			print STDERR "[OK]\n"	
        }
    }
    elsif($response->{hook}) {
		my $name = $response->{hook}->[0];
		my $func = $response->{hook}->[1];
		app_prompt($self->{msghd} . "Hook","$name\n");
		&$func($_,$response,$rule) foreach(@{$data});
    }
	elsif($action =~ m/^COMMAND:\s*(.+?)\s*$/) {
		$action = $1;
		app_prompt($self->{msghd} . 'Action',"$action\n");
		foreach(@{$data}) {
			system("$action \"$_\"");
		}
	}
	elsif($action eq 'SAVE') {
		app_prompt($self->{msghd} . 'Action',"$action\n");
		if(!$PROGRAM_SAVE) {
			$PROGRAM_SAVE = new MyPlace::Program::Saveurl;
			$PROGRAM_SAVE->setOptions("--referer",$base) if($base);
		}
		$PROGRAM_SAVE->addTask(@{$data});
		$PROGRAM_SAVE->execute();
	}
	elsif($action eq 'UPDATE') {
		app_prompt($self->{msghd} . 'Action',"$action\n");
		my $OUTDATE = undef;
		my @RECORDS;
		if(open FI, '<:utf8',"URLS.txt") {
			foreach(<FI>) {
				chomp;
				push @RECORDS,$_;
			}
			close FI;
		}
		my @KEEPS;
		foreach(@{$data}) {
			foreach my $rec(@RECORDS) {
				if($_ eq $rec) {
					$OUTDATE = 1;
					last;
				}
			}
			if($OUTDATE) {
				last;
			}
			else {
				push @KEEPS,$_;
			}
		}
		if(@KEEPS and (open FO,">>:utf8","URLS.txt")) {
			print FO join("\n",@KEEPS),"\n";
			close FO;
			if(!$PROGRAM_SAVE) {
				$PROGRAM_SAVE = new MyPlace::Program::Saveurl;
				$PROGRAM_SAVE->setOptions("--referer",$base) if($base);
			}
			$PROGRAM_SAVE->addTask(@{$data});
			$PROGRAM_SAVE->execute();
		}
		$self->outdated() if($OUTDATE);
	}
    elsif($action) {
		app_prompt($self->{msghd} . 'Action',"$action\n");
        my $childpid = open FO,"|-:utf8",$action;
#		print STDERR "Childpid:$childpid\n";
		if($childpid) {
			print FO join("\n",@{$data}),"\n";
			close FO;
			waitpid($childpid,0);
		}
		else {
			exit 0;
		}
    }
    else {
        print $_,"\n" foreach(@{$data});
    }
}

1;

__END__

