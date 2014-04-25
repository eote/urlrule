#!/usr/bin/perl -w
package MyPlace::URLRule::QvodExtractor;
use strict;
BEGIN {
    require Exporter;
    our ($VERSION,@ISA,@EXPORT,@EXPORT_OK,%EXPORT_TAGS);
    $VERSION        = 1.00;
    @ISA            = qw(Exporter);
    @EXPORT         = qw(&extract_videolinks &extract_article &extract_item &extract_videoinfo &extract_list &extract_pages &extract_catalogs);
    @EXPORT_OK         = qw(&extract_videolinks &extract_article &extract_item &extract_videoinfo &extract_list &extract_pages &extract_catalogs apply_rule process);
}
use MyPlace::URLRule::Utils qw/get_html get_url js_unescape/;
use MyPlace::URLRule qw/urlrule_quick_parse/;
use Encode qw/find_encoding from_to encode decode/;
my $utf8 = find_encoding('utf8');
use utf8;

sub normalize_url {
	my $_ = shift;
	if(m/^http:\/\/adult\.qvod\//) {
		s/^http:\/\/adult\.qvod\///;
	}
	elsif(m/^adult\.qvod\//) {
		s/^adult\.qvod\///;
	}
	if(!m/^[^:\/]+:\/\//) {
		$_ = "http:\/\/$_";
	}
	return $_;
}

sub _build_url {
	my $site = shift;
	my $path = shift;
	my $rel = shift;
	if($rel =~ m/^[^:\/]+:\/\//) {
		return $rel;
	}
	elsif($rel =~ m/^\//) {
		return "$site$rel";
	}
	else {
		return "$site/$path/$rel";
	}
}

sub _parse_url {
	my $_ = shift;
	my $site;
	my $path;
	my $file;
	if(m/^([^:\/]+:\/\/[^\/]+)\/(.+?)\/([^\/]+)$/) {
		$site = $1;
		$path = $2;
		$file = $3;
	}
	elsif(m/^([^:\/]+:\/\/[^\/]+)\/(.+?)\/$/) {
		$site = $1;
		$path = $2;
		$file = '';
	}
	elsif(m/^([^:\/]+:\/\/[^\/]+)\/([^\/]+)$/) {
		$site = $1;
		$path = "";
		$file = $2;
	}
	elsif(m/^([^:\/]+:\/\/[^\/]+)/) {
		$site = $1;
		$path = "";
		$file = '';
	}
	else {
		$site = $_;
		$path = '';
		$file = '';
	}
	return $site,$path,$file;
}

sub build_url {
	my $base = shift;
	my $rel = shift;
	if($rel =~ m/^[^:\/]+:\/\//) {
		return $rel;
	}
	my ($site,$path,undef) = _parse_url($base);;
	return _build_url($site,$path,$rel);
}

use MyPlace::String::Utils qw/dequote/;

sub normalize_title {
	my $_ = shift;
	s/^\s+//;
	s/\s+$//;
	if(m/^最新(.+),好看的\1排行/) {
		$_ = $1;
	}
	if(m/^有什么好看的([^,]+).*$/) {
		$_ = $1;
	}
	$_ = dequote($_);
	s/^好看的//;
	s/[\/\|\\\:\*\?]+/_/g;
	s/_*作者\s*[：_]\s*不详_*//g;
	s/\s+_/_/g;
	s/__+/_/g;
	s/^[\s_]+//;
	s/[_\s]+$//;
	return $_;
}
sub build_my_url {
	my $base = shift;
	my $urls = shift;
	my $flag = shift;
	if($urls && defined $urls->[0]) {
		my($site,$path,undef) = _parse_url($base);
		if($flag) {
			foreach(@$urls) {
				$_ = "http://adult.qvod/" . _build_url($site,$path,$_);
			}
		}
		else {
			foreach(@$urls) {
				$_ = _build_url($site,$path,$_);
			}
		}
	}
	return $urls;
}

sub patch_result {
	my $base = shift;
	my $r = shift;
	my $topurl = shift;
	$r->{title} = normalize_title($r->{title}) if($r->{title});
	$r->{work_dir} = normalize_title($r->{work_dir}) if($r->{work_dir});
	my $flag = 0;
	if($topurl && $topurl =~ m/^http:\/\/adult\.qvod/) {
		$flag = 1;
	}
	build_my_url($base,$r->{pass_data},$flag) if($r->{pass_data});
	build_my_url($base,$r->{data},$flag) if($r->{data});
	return $;
}

sub html2txt {
	my $_ = $_[0];
	if(m/<[bB][rR]\s*\/>[　\s]*<[bB][rR]\s*\/>/) {
		s/<[bB][rR]\s*\/>[　\s]*<[bB][rR]\s*\/>/\r\n/g;
		s/<[bB][rR]\s*\/>//g;
	}
	elsif(m/<[bB][rR]\s*>[　\s]*<[bB][rR]\s*>/) {
		s/<[bB][rR]\s*>[　\s]*<[bB][rR]\s*>/\r\n/g;
		s/<[bB][rR]\s*>//g;
	}
	else {
		s/<[bB][rR]\s*\/>/\r\n/g;
		s/<[bB][rR]\s*>/\r\n/g;
	}
	s/&ldquo;/“/g;
	s/&rdquo;/”/g;
	s/<[^>]*>//g;
	return $_;
}
	sub new_file_data {
		my $content = shift;
		my $ext = shift(@_) || '.txt';
		my $tmpfile=`mktemp -t --suffix=$ext tmp.XXXXXXXX`;
		chomp($tmpfile);
		open FO,'>:utf8',$tmpfile or return (error=>$!);
		print FO "$content\n";
		close FO;
		return $tmpfile;
	}

sub build_html_page {
	my $content= shift;
	my $title = shift;
	my $base = shift;
	my $r = '
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
<html xmlns="http://www.w3.org/1999/xhtml">
<head>
<meta http-equiv="Content-Type" content="text/html; charset=utf-8" />';
$r = $r . "\n<title>$title</title>" if($title);
$r = $r . "\n<base href=\"$base\"> " if($base);
$r = $r . "\n</head>\n<body>\n" . $content . "\n</body>\n</html>";
return $r;
}

sub nothing_msg {
	return (
		count=>0,
		message=>join("\n",@_),
	);
}
sub error_msg {
	return (
		'error'=>join("\n",@_),
	);
}

sub extract_article {
	my %D = @_;
	my $url=$D{url};
	my $html=$D{html};
	$html = get_html($url,'-v') unless($html);
	return error_msg("Failed retriving $url.") unless($html);
    my @html = split(/\n/,$html);
	my $title;
	my $f_text;
	my $ext='.txt';
	my @data=();
	my $content;
	my @text_strip;
	if($D{articleContent}) {
		@text_strip = @{$D{articleContent}};
	}
	else {
		@text_strip = (
			'<div class="(?:novel|pic)Content">(.+?)<\/div>',
			'<div class=temp22[^>]*>(.+?)<\/div>',
			'div id="twcc">(.+)<div class="gecns"',
			'(<DIV class=title>.+?</DIV></DIV>)',
			'<div class="n_bd">(.+?)</p>',
		);
	}
	if($D{articleTitle}) {
		if($html =~ m/$D{articleTitle}/) {
			$title = $1;
		}
	}
	else {
		if($html =~ m/<[Tt][Ii][Tt][Ll][Ee]>([^<]+?)\s*-\s*[^<-]+<|<[Tt][Ii][Tt][Ll][Ee]>\s*([^<]+?)\s*</) {
			$title = $1 || $2;
		}
	}
	foreach my $exp(@text_strip) {
		if($html =~ m/$exp/s) {
			$content = $1;
		}
	}
	return nothing_msg("Missing article content, Or not a article.") unless($content);
#	print STDERR "$content\n";
	if($content =~ m/(?:src|href)\s*=|<\s*(?:object|embed)|thunder:/) {
		$ext=".html";
		$content = build_html_page($content,$title);
	}
	else {
		$content = $title ."\n" . html2txt($content);
	}
	if(!$title) {
		return (error=>"Invalid page.");
	}
	my $tmpfile = new_file_data($content,$ext);
	$title = normalize_title($title);
	push @data,"file://$tmpfile\t$title$ext";
	my $img=0;
	my %imgs;
	while($content =~ m/<[Ii][Mm][Gg][^<]*[Ss][Rr][Cc]\s*=\s*['"]([^'"]+)['"]/g) {
		next if($imgs{$1});
		$imgs{$1} = 1;
		$img++;
		my $url = $1;
		my $ext = ".jpg";
		if($url =~ m/^http:\/\/([^\/\.]*\.?)([^\/]+)\.\/(.+)$/) {
			$url = $1 eq "." ? "http://www.$2.com/$3" : "http://$1$2.com/$3";
		}
		if($url =~ m/\/.*(\.[^\.\/]+)$/) {
			$ext = $1;
		}
		push @data,"$url\t$title\." . strnum($img,3) . $ext;
	}
	my $count=scalar(@data);
	return (
		base=>$url,
		data_count=>$count,
		data=>\@data,
		title=>($count>3 ? $title : undef),
	);
}

sub strnum {
	my $val = shift;
	my $numlen = shift(@_) || 0;
	return $val if($numlen<2);
	return $val if($val >= (10**$numlen));
	my $str = "0"x$numlen . $val;
	return substr($str,length($str) - $numlen);
}

sub extract_videolinks {
	my %D = @_;
	my $url=$D{url};
	my $html=$D{html};
	$html = get_html($url,'-v') unless($html);
	return error_msg("Failed retriving $url.") unless($html);
	$html =~ s/\\u(....)/\\x{$1}/g;
	$html =~ s/%7C/|/g;
	my %qvod = (
		'qvod'=>[],
		'bdhd'=>[],
		'unknown'=>[],
		'qvodcount'=>0,
		'bdhdcount'=>0,
		'unknowncount'=>0,
	);
	my @exps;
	if($D{qvodlinks}) {
		@exps = @{$D{qvodlinks}};
	}
	else {
		@exps = (
			'\'([^\']+)\$([^\']+?)\$(?:bdhd|qvod)\'',
			'([^\'"\|\$]*)\$((?:bdhd|qvod):\/\/\d+\|\w+\|[^\'"\|\$]+?\|?)[#\':]+',
			'url = "((?:qvod|bdhd|ed2k)://[^"]+)"',
			'([^"]+?)%2B%2B((?:qvod|bdhd|ed2k)%3A%2F%2F[^"]+?)(?:%2B%2B%2B|")',
		);
	};
	my $matched;
	foreach my $exp(@exps) {
		last if($matched);
		my $idx=0;
		while($html =~ m/$exp/g) {
			$matched = 1;
			$idx++;
			my $part1 = $1;
			my $part2 = $2;
			if(!$part2) {
				$part2 = $part1;
				$part1 = strnum($idx,3);
			}
			foreach($part1,$part2) {
				s/"+$//;
				s/^"+//;
				s/%E7%AC%AC/第/g;
				s/%E9%9B%86/集/g;
				$_ = js_unescape($_);
				if(m/\\u|\\x/) {
					$_ = (eval("\"\" . \"$_\""));
				}
			}
			my $ext = '';
			my $url = lc($part2);
			if($url =~ m/^(?:qvod|bdhd|http):\/\/.*(\.[^\.\|\/]+?)\|?$/) {
				$ext = $1;
			}
			elsif($url =~ m/^ed2k:\/\/\|file\|[^\|]+(\.[^\.\|\/]+)\|/) {
				$ext = $1;
			}
			if($url =~ m/(\.[^\.\|\/]+?)\|?$/) {
				$ext = $1;
			}
			if($url =~ m/^(?:qvod|http|bdhd)/) {
				push @{$qvod{qvod}},[$part2,$part1,$ext];
				$qvod{qvodcount}++;
			}
			elsif($url =~ m/^(?:ed2k)/) {
				push @{$qvod{bdhd}},[$part2,$part1,$ext];
				$qvod{bdhdcount}++;
			}
			else {
				push @{$qvod{unknown}},[$part2,$part1,$ext];
				$qvod{unknowncount}++;
			}
		}
	}
	return \%qvod;
}


sub extract_videoinfo {
	my %D = @_;
	my $url=$D{url};
	my $html=$D{html};
	$html = get_html($url,'-v') unless($html);
	return error_msg("Failed retriving $url.") unless($html);
	my %r;
	my @lines = split("\n",$html);
	my @cover;
	my @text_strip;
	if($D{content}) {
		@text_strip = @{$D{content}};
	}
	else {
		@text_strip = (
		'<div class="m-info">(.+?)<div class="mtext">',
		'<div class="mainArea">(.+?)<div class="bbg',
		'(<ul class="movieintro">.+?<\/ul>)',
		'(<div class="intro">.+?</div>)</td>',
		'(<p class="twW50">.+?)<p class="twW90" id="ckepop">',
		'<DIV class="info">(.+?)<DIV class="wenzi">',
		'(<DIV class=info>.+?</DIV></DIV></DIV>)',
		'<DIV class="info">(.+?)<div class="plstyle">',
		'<div id="idDIV"> <p>(.+?)<\/p> <\/div>',
		'<div class="video-box">(.+?)<div class="correlation">',
		'<div id="classpage">(.+?<\/[Uu][Ll]>)',
		'<div class="ContentImg">(.+?)<a[^>]*href=',
		'<div class="main">(.+?)<div id="footer">',
		);
	}
	my $cover_exp = $D{cover} || 'class="cover"><[Ii][Mm][Gg] src="([^"]+)"';
	my $playurl_exp = $D{playurl} || '<a[^>]*href=[\'"]([^\'"]*\/(?:sogou\/index|vod-play-id-|playmovie\/\d+|player\/|video\/|kk\/index)[^\'"]+)';
	my @title_exp = ($D{itemTitle}) || (
		'<li[^>]*class=[\'"]title[\'"][^>]*>([^<]+)',
		'<[Tt][Ii][Tt][Ll][Ee]>\s*([^<]+?)\s*(?:_qvod高清在线观看)',
		'<[Tt][Ii][Tt][Ll][Ee]>\s*([^<]+?)\s*(?:全集在线观看|在线播放|在线观看|快播Qvod在线播放)',
		'<[Tt][Ii][Tt][Ll][Ee]>\s*正在播放\s*([^<]+)\s*',
	);


	my $catalog_exp = $D{catalog} || '(?:分类|类型)\s*[:：]+\s*<[^>]+>\s*([^<]+)';
	my $text_start;
	foreach(@lines) {
		while(m/$cover_exp/g) {
			$r{cover} = [] unless($r{cover});
			push @{$r{cover}},$1 || $2 || $3;
		}
		if(!$r{playurl}) {
			if($playurl_exp eq '#self') {
				$r{playurl}=$url;
			}
			elsif(m/$playurl_exp/) {
				$r{playurl} = $1;
			}
		}

		if(!$r{title}) {
			foreach my $title_exp(@title_exp) {
				if(m/$title_exp/) {
					$r{title} = $1;
					$r{title} =~ s/\s*[-_]?\s*剧情介绍.*$//;
					$r{title} =~ s/^\s*《(.+?)》\s*$/$1/;
					$r{title} = normalize_title($r{title});
					last;
				}
			}
		}
	}
	foreach my $exp (@text_strip) {
		if($html =~ m/$exp/s) {
			$r{text} = $1;
			$r{content} = $1;
			last;
		}
	}
	if($r{text}) {
		my %imgs;
		while($r{text} =~ m/<[Ii][Mm][Gg][^<]*\s+[Ss][Rr][Cc]=['"]([^'"]+)['"]/g) {
			$r{cover} = [] unless($r{cover});
			next if($imgs{$1});
			$imgs{$1} = 1;
			my $src = $1;
			next if($src =~ m/qvod_download|\.png/);
			if($src =~ m/^http:\/\/([^"]+)\.\/(.+)$/) {
				$src = "http://$1.com/$2";
			}
			push @{$r{cover}},$src;
		}
	#	if(!$r{catalog} &&	$r{text} =~ m/(?:分类|类型)\s*[:：]\s*<[^>]+>\s*([^<]+)/m) {
		if(!$r{catalog} &&	$r{text} =~ m/$catalog_exp/m) {
			$r{catalog}=$1;
		}
		$r{text} = undef if(length($r{text})<1024);
	}
	if($r{title}) {
		if($r{title} =~ m/^\s*\(([^\)]+)\)\s*[^\(]+.*$/) {
			$r{catalog} = $r{catalog} ? "$r{catalog}/$1" : $1;
		}
		elsif($r{title} =~ m/^([^：]+)\s*：.+$/) {
			$r{catalog} = $r{catalog} ? "$r{catalog}/$1" : $1;
		}
	}
	return \%r;
}

sub extract_item {
	my %D = @_;
	my $url=$D{url};
	my $article_exp = $D{article} || '\/article\/|\/picbook\/|\/text\d*\/|\/photo\d*\/';
	if($url =~ m/$article_exp/){
		return extract_article(%D);
	}
	my ($site,$path) = _parse_url($url);
	my $html = get_html($url,'-v');
	return error_msg("Failed retriving $url.") unless($html);
	my $detail = extract_videoinfo(%D,html=>$html);
	my @cover;
	my $text;
	my $playurl;
	my $content;
	if($detail) {
		@cover = @{$detail->{cover}} if($detail->{cover});
		$text = $detail->{text};
		$content = $detail->{content};
		$playurl = _build_url($site,$path,$detail->{playurl}) if($detail->{playurl});
	}
	if(!$playurl) {
		$playurl = $url;
	}
	else {
		$html = get_html($playurl,'-v');
		return error_msg("Failed retriving $playurl.") unless($html);
	}
    my $title = $detail->{title};
    my @data;
    my @pass_data;
	my $url3;
    my @html = split(/\n/,$html);
	foreach(@html) {
		if(m/src=['"]([^'"]*\/playdata\/[^'"]+)/) {
			$url3 = _build_url($site,$path,$1);
			last;
		}
	}
	my $qvod;
	if(!$url3) {
		$qvod = extract_videolinks(%D,url=>$playurl,html=>$html);
	}
	else {
		$html = get_url($url3,'-v');
		use Encode qw/decode/;
		$html = decode("gbk",$html);
		return error_msg("Failed retriving $url3.") unless($html);
		$qvod = extract_videolinks(%D,url=>$url3,html=>$html);
	}
	my $videocount = 0;
	if($qvod && ref $qvod) {
#		use Data::Dumper;print Dumper($qvod);
		foreach my $type (qw/qvod bdhd/) {
			my $count = $qvod->{$type . "count"};
			$videocount +=$count;
			my @qvod = @{$qvod->{$type}};
			if((!$title) && $count>0) {
				foreach(@qvod) {
					push @data,"$type:" . $_->[0];
				}
			}
			elsif($count > 1) {
				foreach(@qvod) {
					my $url = "$type:" . $_->[0];
					my $part = $_->[1] ? "_$_->[1]" : "";
					my $ext = $_->[2];
					push @data,"$url\t$title$part$ext";
				}
			}
			elsif($count == 1) {
				push @data,"$type:" . $qvod[0]->[0] . "\t" . $title . $qvod[0]->[2];
			}

		}
	}
	if($videocount < 1) {
		return extract_article(%D,url=>$url,html=>$html);
	}
	if(@cover) {
		my $idx = 1;
		foreach(@cover) {
			my $url = $_;
			my $ext = ".jpg";
			if($url =~ m/\/.*(\.[^\.\/]+)$/) {
				$ext = $1;
			}
			my $prefix = $idx == 1 ? "" : "." . strnum($idx,3);
			push @data,_build_url($site,$path,$url) . "\t${title}$prefix$ext";
			$idx++;
		}
	}
	if($text) {
		$text = build_html_page($text,$title,$url);
		my $tmpfile = new_file_data($text,'.html');
		push @data,'file://' . "${tmpfile}\t${title}\.html";
	}
	if(scalar(@data) <4) {
		$title = "";
	}
	elsif($detail->{catalog}) {
		$detail->{catalog} .= "/$title";
	}
	else {
		$detail->{catalog}=$title;
	}

    return (
        count=>scalar(@data),
        data=>\@data,
        pass_count=>0,
		work_dir=>$detail->{catalog},
		detail=>$detail,
    );
}

sub extract_list {
		my %D = @_;
		my $url = $D{url};
		my $html = $D{html};
		if(!$html) {
			$html = get_html($url,"-v");
			return error_msg("Failed retriving $url.") unless($html);
		}
		my @html = split("\n",$html);
		my %r;
		$_=$html;
		my $title_exp = $D{listTitle} ? [$D{listTitle}] : [
					'<\s*[Tt][iI][Tt][Ll][Ee]\s*>\s*([^<\s_]+)-第\d+页',
					'<\s*(?:title|TITLE)\s*>\s*([^<\s_]+)',
				];
		foreach my $exp(@{$title_exp}) {
			if(m/$exp/) { 
				$r{title} = $1;
				$r{title} = normalize_title($r{title});
				last;
			}
		}
		$r{pass_data}=[];
		my @list_exp;
		if($D{list}) {
			@list_exp = @{$D{list}};
		}
		else {
			@list_exp = qw{
				<div\s*class="intro"><h6><a\s*href="([^"]+)
				<li><a[^>]*href="([^"<]*\/html\/(?:photo|movie|text)\d+\/\d+\.html?)
				class="tit"><a[^>]*href="([^"]+\/vodhtml\/[^"]+)
				(?:[hH]3|[Hh]2)><[Aa][^<]*href=[\'"]((?:\/hao360\/index|\/movie\/index|\/detail\/\?|\/bibi\/index|\/view\/index|\/html\/article\/index)\d+[^\'"]*)"
				span><a\s*href=[\'"]((?:\/html\/article\/index|a)\d+[^\'"]*)[\'"]\s*title="
				<td[^>]*><[aA][^>]*href=['"](\/[^'">\/]+\/\d+\/)['"]
				<(?:TD|td|P\s*class=p2)[^>]*>[^<]*<[aA][^>]*href=['"]([^'"]+)
				<li><a[^>]*href=['"]([^'"]*\/html\/article\/index\d+\.html?)
				<div[^>]*class="pic"[^>]*><a[^>]*href=['"]([^'"]*\/view\/index\d+\.html?) 
				<[Aa][^>]*href=['"]([^'"<]*\/[^\/<]+\/\d+[^\/"'<]+)['"]\s*title=
			};
		}
		foreach my $exp (@list_exp) {
			while($html =~ m/$exp/g) {
#				print STDERR $exp,"\n";
				push @{$r{pass_data}},$1;
			}
			last if($r{pass_data} && @{$r{pass_data}});
		}
		$r{url} = $url;
		$r{base} = $url;
		return %r;
}

sub extract_pages {
		my %D = @_;
		my $rurl = $D{url};
		my $url = $D{ourl};
		my $html = $D{html};
		if(!$html) {
			$html = get_url($rurl,"-v");
			return error_msg("Failed retriving $rurl.") unless($html);
		}
		my @exps;
		if($D{pages}) {
			@exps = @{$D{pages}};	
		}
		else {
			@exps = (
				'<[Aa][^>]*href=\s*["\']([^"\']*\/vod-show-id-\d+-p-)(\d+)(\.html)["\']',
				'<a href=[\'"]([^\'"]*\/(?:photo|movie|text)\d+\/list_)(\d+)(\.html?)',
				'href="([^"]*\/vodlist\/\d+_)(\d+)(\.html)"',
				'<[Aa][^>]*href=[\'"]([^\'"<]*\/list\/[\d\-]+\/index_)(\d+)([^\/"\'<]+)[\'"]',
				'<a href=["\']([^\'"]*\/(?:cn\/index|flei\/index|list\/|part\/|list\/index|list\/\?|cha\/index|html\/part\/index)\d+[-_])(\d+)(\.html?)',
				'<[Aa][^>]*href=[\'"]([^\'"<]*\/[^\/<]+\/index_)(\d+)([^\/"\'<]+)[\'"]',
				'<[Aa][^>]*href=[\'"](index_)(\d+)([^\/"\']+)[\'"]',
			);
		}
		my %r;
		foreach(@exps) {
			next unless($html =~ m/$_/);
			%r = urlrule_quick_parse(
				"url"=>$rurl,
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
				url=>$rurl,
				pass_data=>[$rurl]
			);
		}
		else {
			patch_result($rurl,\%r,$url);
		}
		return %r;
}
sub extract_catalog {
		my %D = @_;
		my $rurl = $D{url};
		my $url = $D{ourl};
		my $html = $D{html};
		if(!$html) {
			$html = get_url($rurl,"-v");
			return error_msg("Failed retriving $rurl.") unless($html);
		}
		my @exps;
		if($D{catalogs}) {
			@exps = @{$D{catalogs}};	
		}
		else {
			@exps = (
				'<a href=["\']([^\'"]*\/(?:flei\/index|list\/|list\/index|list\/\?|cha\/index|html\/part\/index)\d+\.html)',
			);
		}
		my %r;
		foreach(@exps) {
			next unless($html =~ m/$_/);
			%r = urlrule_quick_parse(
				"url"=>$rurl,
				html=>$html,
				'pass_exp'=>$_,
				'pass_map'=>'$1',
			);
			last;
		}
		if((!%r) || (!$r{pass_data}) || !($r{pass_data}->[0])) {
			return nothing_msg("Extract nothing\n");
		}
		else {
			patch_result($rurl,\%r,$url);
		}
		return %r;
}
sub apply_rule {
	my $url = shift;
	my $rule = shift;
	my $level = $rule->{level} || 0;
	my $rurl = normalize_url($url);
	if($level <1 ) {
		return extract_item(url=>$rurl,rule=>$rule,ourl=>$url);
	}
	if($level == 1) {
		return extract_list(url=>$rurl,rule=>$rule,ourl=>$url);
	}
	elsif($level == 2) {
		return extract_pages(url=>$rurl,ourl=>$url,rule=>$rule);
	}
	elsif($level == 3) {
		return extract_catalog(url=>$rurl,ourl=>$url,rule=>$rule);
	}
	else {
		return (
			"error"=>"no handler defined for [$level] $url \n",
		);
	}
}

sub process {
	my %D = @_;
	my $level = $D{rule}->{level} || 0;
	if($level <1) {
		return extract_item(%D);
	}
	elsif($level == 1) {
		return extract_list(%D);
	}
	elsif($level == 2) {
		return extract_pages(%D);
	}
	elsif($level == 3) {
		return extract_catalog(%D);
	}
	else {
		return error_msg("No handler defined for [$D{level}] $D{url}");
	}
}


1;

__END__

#       vim:filetype=perl
