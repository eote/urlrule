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
    @EXPORT_OK      = qw(&new_json_data &get_url &parse_pages &unescape_text &get_html &decode_html &js_unescape &strnum new_html_data &expand_url &create_title &extract_text &html2text);
}
use Encode qw/from_to decode encode/;
use MyPlace::Curl;


my $cookie = $ENV{HOME} . "/.curl_cookies.dat";
my $cookiejar = $ENV{HOME} . "/.curl_cookies2.dat";
my $curl = MyPlace::Curl->new(
	"location"=>'',
	"silent"=>'',
	"show-error"=>'',
	"cookie"=>$cookie,
	"cookie-jar"=>$cookiejar,
#	"retry"=>4,
	"max-time"=>120,
);

sub new_html_data {
	my $html = shift;
	my $title = shift;
	my $base = shift;
	my $r = '
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
<html xmlns="http://www.w3.org/1999/xhtml">
<head>
<meta http-equiv="Content-Type" content="text/html; charset=utf-8" />';
$r = $r . "\n<title>$title</title>" if($title);
$r = $r . "\n<base href=\"$base\"> " if($base);
$r = $r . "\n</head>\n<body>\n" . $html . "\n</body>\n</html>";
$r =~ s/\n/\0/sg;
	return "data://$r\t$title.html";
}

sub hash2str {
	my %data = @_;
	my $r = "{";
	foreach(keys %data) {
		my $rt = ref $data{$_};
		if(!$rt) {
			$r = $r . "'$_':'$data{$_}',";
		}
		elsif($rt eq 'ARRAY') {
			$r = $r . "'$_':['" . join("','",@{$data{$_}}) . "'],";
		}
		elsif($rt eq 'HASH') {
			$r = $r . "'$_':" . hash2str(%{$data{$_}}) . ","; 
		}
		else {
			$r = $r . "'$_':'$data{$_}',";
		}
	}
	$r .= "};";
	return $r;
}

sub new_json_data {
	my $varname = shift;
	my $filename = shift;
	die "data://$varname = " . hash2str(@_) . "\t$filename.json";
	return "data://$varname = " . hash2str(@_) . "\t$filename.json";
}


sub strnum {
	my $val = shift;
	my $numlen = shift(@_) || 0;
	return $val if($numlen<2);
	return $val if($val >= (10**$numlen));
	my $str = "0"x$numlen . $val;
	return substr($str,length($str) - $numlen);
}
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
	my $verbose = shift(@_) || '-q';
	my $silent;

	my $retry = 4;
	return undef unless($url);

	if(!$verbose) {
	}
	elsif('-q' eq "$verbose") {
		$verbose = undef;
		$silent = 1;
	}
	elsif('-v' eq "$verbose") {
		$verbose = 1;
		$silent = undef;
	}
	else {
		unshift @_,$verbose;
		$verbose = undef;
		$silent = undef;
	}

	my $data;
	my $status;
	print STDERR "[Retriving URL] $url ..." if($verbose);
	while($retry) {
		($status,$data) = $curl->get($url,@_);
		if($status != 0) {
			print STDERR "[Retry " . (5 - $retry) . "][Retriving URL] $url ..." if($verbose);
		}
		else {
			print STDERR "\t[OK]\n" unless($silent);
			last;
		}
		$retry--;
		sleep 3;
	}
	if(wantarray) {
		return $status,$data;
	}
	else {
		return $data;
	}
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
#	from_to($html,$charset,'utf-8');
	$html = decode($charset,$html);
	return $html;
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
		$last = $d{limit} if($d{limit} and $d{limit} < $last);
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

sub create_title {
	my $title = shift;
	my $nodir = shift;
	$title = unescape_text($title);
	return unless($title);
	if($nodir) {
		$title =~ s/[<>\?*\:\"\|\/\\]+/_/g;
	}
	else {
		$title =~ s/[<>\?*\:\"\|]+/_/g;
	}
	$title =~ s/__+/_/g;
	return $title;
}

sub expand_url {
	my $url = shift;
	if($url =~ m/^http:\/\/url.cn/) {
		open FI,'-|',"curl -v -- \"$url\" 2>&1" or return $url;
	}
	else {
		open FI,'-|','curl','--silent','-I',$url or return $url;
	}
	foreach(<FI>) {
		chomp;
		if(m/^<?\s*Location:\s*(http:.+)$/) {
			my $loc = $1;
			$loc =~ s/\s+$//;
			print STDERR "$url => $loc\n";
			return $loc;
		}
	}
	return $url;
}

sub extract_text {
	my $sortedKeys = shift;
	my $defs = shift;
	my %in;
	my %done;
	my %r;

		foreach my $k((@$sortedKeys)) {
			next unless(defined $defs->{$k});
			next if($done{$k});
			foreach(@_) {
				if($in{$k} and m/$defs->{$k}->[1]/i) {
					push @{$r{$k}},$_;
					$in{$k} = 0;
					$done{$k} = 1;
					last;
				}
				elsif($in{$k}) {
					push @{$r{$k}},$_;
					next;
				}
				elsif(m/$defs->{$k}->[0]/i) {
					if(!$defs->{$k}->[1]) {
						$r{$k} = $1 ? $1 : $_;
						$done{$k} = 1;
						last;
					}
					$in{$k} = 1;
					push @{$r{$k}},$_;
					next;
				}
			}
		}	
	return %r;
}

sub html2text {
	my @text = @_;
	my @r;
	foreach(@text) {
		next unless($_);
		s/[\r\n]+$//;
		s/<\/?(?:br|td)\s*>/###NEWLINE###/gi;
		s/<\/p\s*>/###NEWLINE######NEWLINE###/gi;
		s/\s*<[^>]+>\s*//g;
		s/###NEWLINE###/\n/g;
		next unless($_);
		push @r,$_;
	}
	if(wantarray) {
		return @r;
	}
	else {
		return join("\n",@r);
	}

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

