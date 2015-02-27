#!/usr/bin/perl -w
package MyPlace::URLRule::Database;
use strict;
use warnings;
use File::Spec;
use MyPlace::Config;
use MyPlace::HashArray;

my @CONFIG_INC = (
	File::Spec->curdir,
	File::Spec->catdir($ENV{HOME} ,'.urlrule','database'),
	File::Spec->catdir($ENV{HOME},'.urlrule'),
);


sub new {
	my $class = shift;
	my $self = bless {@_},$class;
	$self->{database} = "DATABASE.ud" unless($self->{database});
	$self->{hosts} = "HOSTS.ud" unless($self->{hosts});
	$self->{names} = "NAMES.db" unless($self->{names});
	$self->init();
	return $self;
}

sub is_dirty {
	my $self = shift;
	return $self->{Database}->{dirty};
}
sub save {
	my $self = shift;
	return $self->{Database}->write_plainfile($self->{file_database});
}

sub add {
	my $self = shift;
	return $self->{Database}->add(@_);
}

sub locate_file {
	my $self = shift;
	my $filename = shift;
	return $filename if(-f $filename);
	foreach(@CONFIG_INC) {
		my $f = File::Spec->catfile($_,$filename);
		return $f if(-f $f);
	}
	return $filename;
}

sub init {
	my $self = shift;

	foreach my $fn (qw/database names hosts/) {
		$self->{"file_$fn"} = $self->locate_file($self->{$fn});
	}
	$self->{Database} = MyPlace::Config->new();
	$self->{Database}->read_plainfile($self->{file_database});
	$self->{Names} = MyPlace::HashArray->read($self->{file_names});
    $self->{Hosts} = MyPlace::Config->new();
    $self->{Hosts}->read_plainfile($self->{file_hosts});
	return $self;
}

sub dbfiles {
	my $self = shift;
	return $self->{file_database},$self->{file_names};
}

sub query {
	my $self = shift;
	my @queries = @_;
	@queries = ('/.?/') unless(@queries);
	my @targets;
	foreach(@queries) {
		next unless($_);
		my @q = split(/\s*,\s*/,$_);
		foreach(@q) {
			$_ = '/.?/' unless($_);
		}
		$_ = join(",",@q);
		my @r =  $self->{Database}->query($_);
		if(!@r) {
			next unless(m/^[^,]+,[^,]+,[^,]+$/);
		}
		if((!@r) and $_ !~ m/\/,/) {
			@r = ([split(/\s*,\s*/,$_),'newly']);
		}
		push @targets,@r if(@r);
	}
    my @records = $self->{Database}->get_records(@targets);
    return $self->convert_records(\@records);
}

sub name_exp {
	my $exp = shift;
	my @values = @_;
	if($exp =~ m/(\{([LlUu]?)[Nn][Aa]([^\w])?[Mm][Ee]\})/) {
		my $m = $1;
		my $case =$2 || "";
		my $sp = $3;
		foreach(@values) {
			if($case eq 'L') {
				$_ = lc($_);
			}
			elsif($case eq 'l') {
				s/\b(.)/\L$1/g;
			}
			elsif($case eq 'U') {
				$_ = uc($_);
			}
			elsif($case eq 'u') {
				s/\b(.)/\U$1/g;
			}
			s/ /$sp/g if($sp);
		}
		$exp =~ s/\{[LlUu]?[Nn][Aa][^\w]?[Mm][Ee]\}/{name}/g;
	}
	if($exp =~ m/(.)\{name\}\1/) {
		map {$_ = "$1$_$1";} @values;
		$exp =~ s/(.)\{name\}\1/\{name\}/g;
	}
	my $rpl = join(" OR ",@values);
	$exp =~s/\{name\}/$rpl/g;
	return $exp;
}

sub convert_records {
	my $self = shift;
	my @records = @_;
	my $Hosts = $self->{Hosts};
	my $Names = $self->{Names};
    my @r;
    foreach my $record (@records) {
        foreach my $path (@{$record}) {
            my($name,$id,$host) = @{$path};
            next unless($name);
            next unless($id);
            next unless($host);
			#use Data::Dumper;print Data::Dumper->Dump([$path],['path']),"\n";
			if($id =~ m/\{[LlUu]?[Nn][Aa][^\w]?[Mm][Ee]\}/) {
				my @values = ($name);
				if($Names->{$name}) {
					push @values,@{$Names->{$name}};
				}
				$id = name_exp($id,@values);
			}
            if($host =~ m/^#/) {
				#push @r,[$name,$id,$host];
                next;
            }
			my $hostid = $host;
            my $hostname = $host;
            if($host =~ m/^([^\|]+)\|(.*)$/) {
                $hostid = $1;
				$hostname = $2;
            }
            my ($url) = $Hosts->propget($hostid);
            if($url) {
                my ($level) = $Hosts->propget($hostid,$url);
                my ($id_name,@id_text);
				if($id =~ m/^https?:\/\//) {
					$id_name = $id;
				}
				else {
					($id_name,@id_text) = split(/\s*:\s*/,$id);
				}
                $url =~ s/###(?:ID|NAME])###/$id_name/g;
                $url =~ s/\{(?:ID|NAME])\}/$id_name/g;
                my $index = 0;
                foreach(@id_text) {
                    $index++;
                    $url =~ s/###TEXT$index###/$_/g;
                    $url =~ s/\{TEXT$index\}/$_/g;
                }
				$url =~ s/###TEXT\d*###//g;
				$url =~ s/\{TEXT\d*\}//g;
                push @r,{
					name=>$name,
					id=>$id,
					host=>$host,
					url=>$url,
					level=>$level
				};
            }
            else {
                print STDERR "HOST $hostid isn't valid, or not defined in : $self->{file_hosts}\n" .
					"Source: $name $id $host\n"
				;
            }
        }
    }
	if(@r) {
		return 1,@r;
	}
	else {
		return;
	}
}

1;

