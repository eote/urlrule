#!/usr/bin/perl -w
package MyPlace::URLRule::Utils;
use strict;
use warnings;
BEGIN {
    require Exporter;
    our ($VERSION,@ISA,@EXPORT,@EXPORT_OK,%EXPORT_TAGS);
    $VERSION        = 1.00;
    @ISA            = qw(Exporter);
    @EXPORT         = qw();
    @EXPORT_OK      = qw(&get_url &parse_pages &unescape_text &get_html &decode_html &js_unescape);
}
use Encode qw/from_to decode/;
use MyPlace::LWP;
my $lwp = new MyPlace::LWP('progress'=>1);
$lwp->{UserAgent}->timeout(15);

sub js_unescape {
	if(!@_) {
		return;
	}
	elsif(@_ == 1) {
		$_ = $_[0];
        $_ =~ s/%u([0-9a-f]+)/chr(hex($1))/eig;
        $_ =~ s/%([0-9a-f]{2})/chr(hex($1))/eig;
		return $_;
	}
	else {
		my @r;
		foreach(@_) {
			$_ = js_unescape($_);
			push @r,$_;
	    }
		return @r;
	}
}

sub get_url {
	my $url = shift;
	my $verbose = shift;
	return undef unless($url);
	if(!$verbose) {
	}
	elsif($verbose eq '-q') {
		$lwp->{progress} = 0;
	}
	elsif($verbose eq '-v') {
		print STDERR "Retriving $url ";
	}
	else {
		unshift @_,$verbose;
	}
	my ($status,$data,$res) = $lwp->get($url,'timeout',15,@_);
	if(!$status) {
		print STDERR ' [' . $res->status_line . "]\n";
	}
	else {
		print STDERR "\n";
	}
	$lwp->{progress} = 1;
	return $data;
}
sub decode_html {
	my $html = shift;
	my $charset;
	if($html =~ /(<meta[^>]*http-equiv\s*=\s*"?Content-Type"?[^>]*>)/i) {
		my $meta = $1;
		if($meta =~ m/charset\s*=\s*["']?([^"'><]+)["']?/) {
			$charset = $1;
		}
	}
	return $html unless($charset);
	if($charset =~ m/^[Gg][Bb]\d+/) {
		$charset = "gbk";
	}
	return decode($charset,$html);
}

sub get_html {
	my $url = shift;
	my $html = get_url($url,@_);
	return decode_html($html) if($html);
}

sub extract_pages {
	my $url = shift;
	my $rule = shift;
	my @exps = (
			'<[Aa][^>]*href=[\'"]([^\'"<]*\/list\/[\d\-]+\/index_)(\d+)([^\/"\'<]+)[\'"]',
			'<a href=["\']([^\'"]*\/(?:cn\/index|flei\/index|list\/|part\/|list\/index|list\/\?|cha\/index|html\/part\/index)\d+[-_])(\d+)(\.html?)',
			'<[Aa][^>]*href=[\'"]([^\'"<]*\/[^\/<]+\/index_)(\d+)([^\/"\'<]+)[\'"]',
			'<[Aa][^>]*href=[\'"](index_)(\d+)([^\/"\']+)[\'"]',

		);
	my %r;
	my $html = get_html($url,'-v');
	foreach(@exps) {
		next unless($html =~ m/$_/);
		%r = urlrule_quick_parse(
			"url"=>$url,
			html=>$html,
			'pages_exp'=>$_,
			'pages_map'=>'$2',
			'pages_pre'=>'$1',
			'pages_suf'=>'$3',
		);
		last;
	}
	if(!%r) {
		%r = (
			url=>$url,
			pass_data=>[$url]
		);
	}
	else {
		patch_result($url,\%r,$url);
	}
	return %r;
}


sub parse_pages {
	my %d = @_;
	my $url = $d{source};
	my $html = $d{data};
	my $pages_exp = $d{exp};
	my $pages_start = $d{start};
	my $pages_margin = $d{margin};
	my $pages_map = $d{map};
	my $pages_pre = $d{prefix};
	my $pages_suf = $d{suffix};
	my @pass_data = ($url);
	if($pages_exp) {
		$pages_margin = 1 unless(defined $pages_margin);
		$pages_start = 2 unless(defined $pages_start);
        my $last = 0;
        my $pre = "";
        my $suf = "";
        while($html =~ m/$pages_exp/g) {
			my $this = eval $pages_map;
            if($this > $last) {
                    $last = $this;
                    $pre = eval $pages_pre  if($pages_pre);
                    $suf = eval $pages_suf if($pages_suf);
            }
        }
		for(my $i = $pages_start;$i<=$last;$i+=$pages_margin) {
			push @pass_data,"$pre$i$suf";
		}
    }
	return \@pass_data;
}

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
	require URI::Escape;
    $text = URI::Escape::uri_unescape($text);
#    $text =~ s/[_-]+/ /g;
    $text =~ s/[\:]+/, /g;
    $text =~ s/[\\\<\>"\^\&\*\?]+//g;
    $text =~ s/\s{2,}/ /g;
    $text =~ s/(?:^\s+|\s+$)//;
    return $text;
}

1;

__END__
=pod

=head1  NAME

MyPlace::uRLRule::Utils - PERL Module

=head1  SYNOPSIS

use MyPlace::uRLRule::Utils;

=head1  DESCRIPTION

___DESC___

=head1  CHANGELOG

    2012-01-18 23:52  xiaoranzzz  <xiaoranzzz@myplace.hell>
        
        * file created.

=head1  AUTHOR

xiaoranzzz <xiaoranzzz@myplace.hell>


# vim:filetype=perl

