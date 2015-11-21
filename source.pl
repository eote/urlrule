
sub runcmd {
#	print STDERR join(" ",@_),"\n";
	return system(@_) == 0;
}
my @list;
open FI,'<',$0 or die("$!\n");
while(<FI>) {
	last if(m/^\s*__END__\s*$/);
}
while(<FI>) {
	chomp;
	s/^\s+//;
	s/\s+$//;
	next unless($_);
	if(m/^([^\t]+)\s*(?:\t|  )\s*([^\t]+)$/) {
		unshift @list,[$1,$2];
	}
	else {
		push @list,$_;
	}
}
close FI;


my $PERLD = "../perl";
foreach my $file (reverse @list) {
	my $link;
	if(ref $file) {
		$link = $file->[1];
		$file = $file->[0];
	}
	my $dir = $file;
	$dir =~ s/\/[^\/]+$//;
	if(!-d $dir) {
		runcmd(qw/mkdir -pv/,$dir) 
			or die("Error creating directory $dir: $!\n");
	}
	if($link) {
		runcmd('ln','-vsf',$link,$file)
			or 	die("Error creating symbol link: $file -> $link : $!\n");
		next;
	}
	my $source = $file;
	$source =~ s/^bin\///;
	$source =~ s/^lib\//modules\//;
	$source = $PERLD . "/" . $source;
	runcmd(qw/cp -av/,$source,$file) 
		or die("Error coping files: $!\n");
}






__END__


bin/urlrule.pl	../lib/MyPlace/Program/URLRule.pm
bin/urlrule_sites	../lib/MyPlace/Program/SimpleQuery.pm
bin/urlrule_worker	../lib/MyPlace/Tasks/Worker/URLRule.pm
bin/urlrule_action
bin/urlrule_cat
bin/urlrule_database
bin/urlrule_database_add_google
bin/urlrule_download
bin/urlrule_dump
bin/urlrule_feed
bin/urlrule_get
bin/urlrule_host_edit
bin/urlrule_host_get
bin/urlrule_info
bin/urlrule_list
bin/urlrule_new
bin/urlrule_query.pl
bin/urlrule_save
bin/urlrule_savebyid
bin/urlrule_source
bin/urlrule_task
bin/urlrule_task_kill
bin/urlrule_task_newly
bin/urlrule_test
lib/MyPlace/Program/SimpleQuery.pm
lib/MyPlace/Program/URLRule.pm
lib/MyPlace/Tasks/Worker/URLRule.pm
lib/MyPlace/URLRule/Config.pm
lib/MyPlace/URLRule/Database.pm
lib/MyPlace/URLRule/File.pm
lib/MyPlace/URLRule/HostMap.pm
lib/MyPlace/URLRule/HostMapData.pm
lib/MyPlace/URLRule/OO.pm
lib/MyPlace/URLRule/Processor.pm
lib/MyPlace/URLRule/QvodExtractor.pm
lib/MyPlace/URLRule/SaveById.pm
lib/MyPlace/URLRule/SimpleQuery.pm
lib/MyPlace/URLRule/Site.pm
lib/MyPlace/URLRule/Sites.pm
lib/MyPlace/URLRule/Utils.pm
lib/MyPlace/URLRule/Worker.pm
lib/MyPlace/URLRule.pm

