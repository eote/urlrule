#!/usr/bin/perl -w
use strict;
use warnings;
use URI;
use Cwd qw/getcwd/;
use lib '../lib';
use MyPlace::URLRule::OO;
use MyPlace::Script::Message;
my($url,$level) = @ARGV;
if(!$url) {
	$url = 'http://www.gals4free.net/pornstars/sunny-leone.html/';
	$level = 1;
}
my $rule = new MyPlace::URLRule::OO(
	callback_process1=> sub {
		my $self = shift;
		my $response = shift;
		use Data::Dumper;
		print Data::Dumper->Dump([$response],[qw/*response/]),"\n";
	},
	buildurl=>1
);
my $cwd = getcwd;
my $status = $rule->autoApply($url,$level,'COMMAND:echo');
chdir($cwd);
exit($status ? 0 : 2);


