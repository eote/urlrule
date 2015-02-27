#!/usr/bin/perl -w
package MyPlace::Tasks::Worker::URLRule;
use strict;
use warnings;
use parent 'MyPlace::Tasks::Worker';
use MyPlace::Weipai;
use MyPlace::Tasks::Task qw/$TASK_STATUS/;
use MyPlace::Script::Message;
use MyPlace::Program::SimpleQuery;
use MyPlace::URLRule::Utils qw/get_url/;
my $USQ;
#	sub set_workdir {
#		my $wd = shift;
#		return 1 unless($wd);
#		if(! -d $wd) {
#			mkdir $wd or return undef,"Error creating directory $wd:$!";
#		}
#		chdir $wd or return undef,"Error change working directory $wd:$!";
#		return 1;
#	}

	sub build_url {
		my $host = uc(shift(@_));
		my $id = shift;
		if($host eq 'WEIPAI.CN') {
			return MyPlace::Weipai::build_url('video',$id);
		}
		elsif($host eq 'VLOOK.CN') {
			return "http://www.vlook.cn/user_video_list?blog_id=$id";
		}
		else {
			return $id;
		}
	}

	sub expand_url {
		my $url = shift;
		if($url =~ m{^http://url.cn} || $url =~ m{http://[^\.]+\.l\.mob\.com}) {
			print STDERR "Retriving $url ...\n";
			if(open FI,"-|","curl","--progress","-D","/dev/stdout",$url) {
				while(<FI>) {
					chomp;
					if(m/\s*Location\s*:\s*(.+?)\s*$/) {
						print STDERR "URL: $url \n => $1\n";
						close FI;
						return $1;
						last;
					}
				}
				close FI;
			}
			else {
				return;
			}
		}
	}
	sub extract_info_from_url {
		my $url = shift;
		my $host = shift;


		if($url =~ m/^http:\/\/www\.weipai\.cn\/(?:user|videos|follows|fans)\/([^\/\s%&]+)/) {
			my $uid = $1;
			my $info = MyPlace::Weipai::get_data('user',$uid,1);
			return $1,$info->{username},'weipai.cn';
		}
		elsif($url =~ m/weipai\.cn|l\.mob\.com/) {
			my $user = MyPlace::Weipai::get_user_from_page($url);
			if($user) {
				return $user->{uid},$user->{username},'weipai.cn';
			}
			else {
				return undef;
			}
		}
		elsif($url =~ m/vlook\.cn/) {		
			my ($name,$id);
			$url =~ s/^(.*\/[^\/%&\?]+).+?$/$1/;
			my $data = get_url($url,'-v');
			my @text = split("\n",$data);
				if(!$host) {
					$host = 'vlook.cn';
				}
			foreach(@text) {
				chomp;
				if(m/<a[^>]*href="\/mobile\/mta\/home\/qs\/([^"\/\?]+)[^"]*"[^>]*class="user"[^>]*>\s*([^<]+?)\s*<\/a/) {
					$name = $2;
					$id = $1;
					last;
				}
				elsif((!$name) and m/class="personal_head"><img[^>]+?alt="([^"]+?)"/) {
					$name = $1;
				}
				elsif((!$name) and m/<meta name="description" content="([^:"]+)/) {
					$name = $1;
				}
				elsif((!$id) and m/href="\/ta\/follow\/qs\/([^\/&?"]+)/) {
					$id = $1;
				}
				last if($name and $id);
			}
			#die "[$url] => $name, $id\n";
			$name =~ s/的个人视频主页.*$// if($name);
			return $id,$name,$host;
		}
		elsif($url =~ m/miaopai.com/) {
			require MyPlace::MiaoPai;
			my $info = MyPlace::MiaoPai::extract_info($url);
			return $info->{uid},$info->{uname},'miaopai.com';
		}
	}

sub new {
	my $class = shift;
	my $self = $class->SUPER::new(name=>'urlrule',@_);
	$self->{routine} = \&work;
	return $self;
}

sub work {
	my $self = shift;
	my $task = shift;
	my $type = shift;
	if(!$type) {
		return $TASK_STATUS->{ERROR},'No urlrule/type specified';
	}

	my @USQOPTS = ();
	push @USQOPTS,'--no-recursive' if($self->{'no-recursive'});
	push @USQOPTS,'--no-createdir' if($self->{'no-createdir'});
	
	my $WD = $task->{target_dir} || $task->{workdir} || $self->{target_dir} || ".";
	if($type eq 'sites') {
		use MyPlace::Program::SimpleQuery;
		$USQ ||= new MyPlace::Program::SimpleQuery('--thread',1,@USQOPTS);

		my $hosts = shift;
		my $command = shift;
		
		if(!$hosts) {
			return $TASK_STATUS->{ERROR},'No hosts specified';
		}
	
		if(!$command) {
			$task->{summary} = 'No action assicated';
			return $TASK_STATUS->{ERROR};
		}

		my ($CMD,@CMDS_NEXT) = split(/\s*[,\|]\s*/,uc($command));

		if($CMD eq 'ADD') {
		}
		elsif($CMD =~ m/^[ADFUS]+$/) {
			my @CC;
			for(my $i=0;$i<length($CMD);$i++) {
				my $C = substr($CMD,$i,1);
				if($C eq 'A') {
					push @CC,'ADD';	
				}
				elsif($C eq 'D') {
					push @CC,'DOWNLOADER';
				}
				elsif($C eq 'F') {
					push @CC,'FOLLOW';
				}
				elsif($C eq 'U') {
					push @CC,'UPDATE';
				}
				elsif($C eq 'S') {
					push @CC,'SAVE';
				}
			}
			$CMD = shift @CC;
			unshift @CMDS_NEXT,@CC;
		}

		$task->{title} = "[urlrule] sites $hosts $CMD" . 
			($_[0] ? " $_[0]" : "") .
			($_[1] ? " $_[1]" : "");
		
		my $FROMURL = "";
		my $ARG1 = shift(@_);
#		if($CMD =~ m/^SAVEURLS?$/) {
#			if($ARG1 and $ARG1 !~ m/^http/) {
#				$ARG1 = build_url($hosts,$ARG1);
#			}
#		}
		if(!$ARG1) {
			return $TASK_STATUS->{ERROR},'Need more arguments';
		}
		elsif($ARG1 and $ARG1 =~ m/^https?:/) {
				
				my $UURL = expand_url($ARG1);
				if($UURL) {
					app_warning("URL => $UURL\n");
					return work($self,$task,$type,$hosts,$command,$UURL,@_);
				}

				my ($key1,$key2,$key3) = extract_info_from_url($ARG1);
				if(!($key1 or $key2)) {
					return $TASK_STATUS->{ERROR},'Extract information from URL failed';
				}
				unshift @_,($key1,$key2,$ARG1);
				$hosts = $key3 if($key3);
				$FROMURL = join(", ",$key1 || (),$key2 || (),$key3 || ());
				app_message2 "$ARG1 =>\n";
				app_message2 "    ",$FROMURL,"\n";
				$FROMURL = "$ARG1 => $FROMURL ";
		}
		else {
			unshift @_,$ARG1;
		}					
		
		if(@CMDS_NEXT) {
			my $taskscount = 1 + scalar(@CMDS_NEXT);
			my @dt;
			foreach($CMD,@CMDS_NEXT) {
				printf STDERR "+ %s %10s %s\n",$hosts, $_, join(" ",@_);
				my $newtask = new MyPlace::Tasks::Task($task->{namespace},'sites',$hosts,$_,@_);
				foreach(qw/target_dir source_dir workdir options/) {
					$newtask->{$_} = $task->{$_};
				}	
				push @dt,$newtask;
			}
			@CMDS_NEXT = ();
			$task->queue(\@dt,1);
			return $TASK_STATUS->{DONOTHING},"Decompressed to $taskscount tasks";
		}	

		my $URLRULE_SITES_COMMANDS = '^(?:ADD|FOLLOW|!SAVE|SAVE|SAVEURL|UPDATE|SAVEURLS|DOWNLOADER|DATABASE|!DATABASE)$';

#		if($CMD !~ /$URLRULE_SITES_COMMANDS/) {
#			$CMD = 'SAVE';
#			unshift @_,$command;
#		}	
		
#		if(uc($hosts) eq 'FROMURLS') {
#			$CMD = 'ADD';
#			$hosts = undef;
#		}

		
		#Pre Process
		if(@_) {
			my $id = shift;
			my $name  = shift;
			if(!$name) {
				if($id =~ m/^(.+)\t+([^\t]+)$/) {
					$id = $1;
					$name = $2;
					unshift @_,$id,$name;
				}
				else {
					unshift @_,$id;
				}
			}
			else {
				unshift @_,$id,$name;
			}
		}


		if($CMD eq 'ADD' || $CMD eq 'FOLLOW') {
			$WD = $task->{source_dir} || $task->{workdir} || $self->{source_dir} || "";
		}
		my $ERROR_WD = $self->set_workdir($task,$WD);
		return $ERROR_WD if($ERROR_WD);
		
		@USQOPTS = ();
		if($task->{options}) {
			push @USQOPTS,'--no-recursive' if($task->{options}->{'no-recursive'});
			push @USQOPTS,'--no-createdir' if($task->{options}->{'no-createdir'});
		}
		if($CMD eq 'SAVECLIPS') {
			if(open FO,">>",'SAVECLIPS.log') {
				print FO @_,"\n";
				close FO;
			}
			$CMD = "DOWNLOADER";
		}
		if($CMD eq 'SEARCH') {
			my $id = shift;
			my $name = shift;
			my($exit,$r) = $USQ->execute(@USQOPTS,"--hosts",$hosts,"SEARCH",$id,$name);

		}
		elsif($CMD eq 'SAVEURLS') {
			my $id = shift;
			my $name = shift;
			my $URL = shift;
			if(!($id or $name)) {
				return $TASK_STATUS->{ERROR},"Invalid URL $URL";
			}
			my $exitval;
			my $msg = "OK";
			foreach($URL,@_) {
				my ($exit,$r) = $USQ->execute(@USQOPTS,'--hosts',$hosts,'--saveurl',$_,($id or $name));
				if($exit != 0 ) {
					$exitval = 1;
					$msg = "Error saving URL:$_\n";
				}
				elsif($r and $r->{directory}) {
					foreach(@{$r->{directory}}) {
						push @{$task->{dir_updated}},[$WD, $_];
					}
				}
			}
			return ($exitval ? $TASK_STATUS->{ERROR} : $TASK_STATUS->{FINISHED}),$msg;
		}
		elsif($CMD eq 'SAVEURL') {	
			my $id = shift;
			my $name = shift;
			my $URL = shift;
			if(!$URL) {
				return $TASK_STATUS->{ERROR},"No URL specified";
			}
			my($exitval,$r) = $USQ->execute(@USQOPTS,'--hosts',$hosts,'--saveurl',$URL,($id or $name));
			if($exitval == 0) {
				if($r and $r->{directory}) {
					foreach(@{$r->{directory}}) {
						push @{$task->{dir_updated}},[$WD, $_];
					}
				}
				return $TASK_STATUS->{FINISHED},"=> $name/$hosts/$id";
			}
			else {
				return $TASK_STATUS->{ERROR},"Failed";
			}
		}
		elsif($CMD eq 'FOLLOW') {
			my $id = shift;
			my $name  = shift || "";
			my $URL = shift;
			my $UNAME = uc($name);
			if($UNAME =~ /$URLRULE_SITES_COMMANDS/) {
				unshift @_,$name;
				$name = "";
			}
			my $dstd = "sites/$hosts";
			if(! -d $dstd) {
				app_warning("Creating directory [$dstd] ... ");
				if(system("mkdir","-p","--",$dstd)==0) {
					print STDERR "\t[OK]\n";
				}
				else {
					print STDERR "\t$!\t[FAILED]\n";
					return $TASK_STATUS->{ERROR},"Create directory [$dstd] failed:$!";
				}
			}
			if(system('simple_query','-f',"$dstd/follows.txt",'--command','additem',$id,$name)==0) {
				$task->{git_commands}=[['add',"$dstd/follows.txt"]];
				return $TASK_STATUS->{FINISHED}, ($FROMURL ? "${FROMURL}OK" : "OK");
			}
			else {
				return $TASK_STATUS->{DONOTHING},($FROMURL ? "${FROMURL}FAILED" : "FAILED");
			}
	
		}
		elsif($CMD eq 'ADD') {
			my $id = shift;
			my $name = shift;
			my $URL = shift;
			unless($id and $name) {
				return $TASK_STATUS->{ERROR},'No id/name specified';
			}
			app_message2 "\tAdd [$id $name] to database of [$hosts]\n";
			if($USQ->execute(@USQOPTS,'--host',$hosts,'--command','additem','--',$id,$name)==0) {
				return $TASK_STATUS->{DONOTHING},($FROMURL ? "${FROMURL}OK" : "OK");
			}
			else {
				return $TASK_STATUS->{DONOTHING},($FROMURL ? "${FROMURL}FAILED" : "FAILED");
			}
	
		}
		else{
			#(($CMD eq '!SAVE') || ($CMD eq 'SAVE') || ($CMD eq 'UPDATE')) {
			my $key = shift;
			my $info = shift(@_) || "";
			if($key and $key =~ m/^\s*(.+)[\t>](.+?)\s*$/) {
				$key = $1;
				unshift @_,$info;
				$info = $2;
			}
			my @prog = (@USQOPTS,"--hosts",$hosts,'--command',$CMD);
			if($key) {
				push @prog,'--',$key;
			}
			elsif($info) {
				push @prog,'--',$info;
			}
			my ($r,$result) = $USQ->execute(@prog);
			if($result and $result->{directory}) {
				foreach(@{$result->{directory}}) {
					push @{$task->{dir_updated}},[$WD, $_];
				}
			}
			if($r == 0) {
				return $TASK_STATUS->{FINISHED},$FROMURL . 'OK';
			}
			if($r == 2) {
				return $TASK_STATUS->{DONOTHING},$FROMURL . 'Nothing to do';
			}
			elsif($r == 3) {
				return $TASK_STATUS->{ERROR},$FROMURL . 'Error';
			}
			else {
				return $TASK_STATUS->{ERROR},$FROMURL . "Program aborted";
			}
		}
		#else {
		#	return $TASK_STATUS->{ERROR},"Invalid command [$CMD]\n";
		#}
	}
	elsif($type eq 'task') {
		my $ERROR_WD = $self->set_workdir($task,$self->{target_dir});
		return $ERROR_WD if($ERROR_WD);
		my $action = shift;
		my @queries = @_;
		
		if(!$action) {
			return $TASK_STATUS->{ERROR},'No action specified';
		}
	
		if(!@queries) {
			$task->{summary} = 'No query specified';
			return $TASK_STATUS->{ERROR};
		}
	
		my $URLRULE_TASK_ACTIONS = '^(?:UPDATE|DOWNLOAD|ECHO|DUMP)$';
		my $CMD = uc($action);

		if($CMD !~ /$URLRULE_TASK_ACTIONS/) {
			return $TASK_STATUS->{ERROR},"[urlrule task] Invalid action $action";
		}

		$task->{title} = "[urlrule task] $action " . join(" ",@queries);
		my @prog = qw/urlrule_task/;
		if($CMD eq 'DOWNLOAD') {
			push @prog,qw/--action DOWNLOAD --no-urlhist/;
		}
		elsif($CMD eq 'UPDATE') {
			push @prog,qw/--action DOWNLOAD/;
		}
		else {
			push @prog,"--action",$CMD;
		}
		push @prog,@queries;
		print STDERR "-- ",join(" ",@prog),"\n";
		if(system(@prog,@queries) == 0 ) {
			return $TASK_STATUS->{FINISHED},"OK";
		}
		else {
			return $TASK_STATUS->{FINISHED},"FAILED";
		}
	}
	elsif($type eq 'action') {
		my $ERROR_WD = $self->set_workdir($task,$self->{target_dir});
		return $ERROR_WD if($ERROR_WD);
		my $url = shift;
		my $level = shift(@_) || 0;
		my $action = shift(@_) || 'SAVE';
		$task->{title} = "[urlrule action] $url $level $action";
		use MyPlace::URLRule::OO;
		my $URLRULE = new MyPlace::URLRule::OO('action'=>$action,'thread'=>1);
		$URLRULE->autoApply({
				count=>1,
				url=>$url,
				level=>$level,
		});
		if($URLRULE->{DATAS_COUNT}) {
			return $TASK_STATUS->{FINISHED},"OK";
		}
		else {
			return $TASK_STATUS->{DONOTHING},"Nothing to do";
		}
	}
	else {
		return $TASK_STATUS->{ERROR},"[urlrule] Error $type not support";
	}
}

sub execute_task {
	my $self = shift;
	my $task = shift;
	chdir $self->{KEPTWD} if($self->{KEPTWD});
	app_message " * " . ($task->{title} || $task->to_string()) . "\n";
	my ($r,$s) = $self->process($task,$task->content());
	if($task->{summary}) {
		print STDERR $task->{summary},"\n";
	}
	my @NEWTASKS = $task->tasks;
	if(@NEWTASKS) {
		foreach my $ts (@NEWTASKS) {
			my $tss = $ts->[0];
			if(!$tss) {
			}
			elsif(ref $tss eq 'ARRAY') {
				foreach(@$tss) {
					($r,$s) = $self->execute_task($_) if($_);
				}
			}
			else {
				($r,$s) = $self->execute_task($tss)
			}
		}
	}
	return $r;
}

sub execute {
	my $self = shift;
	my $OPTS = shift;
	my $task = MyPlace::Tasks::Task->new('urlrule',@_);
	$task->{options} = $OPTS;
	use Cwd qw/getcwd/;
	$self->{KEPTWD} = getcwd;
	return $self->execute_task($task);
}

1;

package MyPlace::Tasks::Worker::URLRule::Program;
use parent 'MyPlace::Program';
our $VERSION = "1.0";
sub OPTIONS {qw/
	help|h
	directory|d=s
	no-createdir|nc
	no-recursive|nr
/;}
sub USAGE {
	my $appname = $0;
	$appname =~ s/^.*[\/\\]//;
	print STDERR "$appname v$VERSION - URLRule worker\n\n";
	print STDERR "Usage: $appname [--directory <path>] ...\n\n";
	print STDERR "\t$appname sites weipai.cn DOWNLOADER Amanda5275\n";
	print STDERR "\t$appname action http://www.moko.cc/post/12344.html 0 SAVE\n\n";
	print STDERR "Copyright, 2015-, Eotect\n";
	return 0;
}
sub MAIN {
	my $self = shift;
	my $OPTS = shift;
	my $APP = new MyPlace::Tasks::Worker::URLRule;
	$APP->{source_dir} = "urlrule";
	if($OPTS->{directory}) {
		$APP->{target_dir} = $OPTS->{directory};
	}
	exit $APP->execute($OPTS,@_);
}
return 1 if(caller);
my $APP = new MyPlace::Tasks::Worker::URLRule::Program;
exit $APP->execute(@ARGV);


