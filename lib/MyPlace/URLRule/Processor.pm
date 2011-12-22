package MyPlace::URLRule::Processor;

use URI;
use URI::Escape;
use MyPlace::Script::Message;
#use Term::ANSIColor;
use MyPlace::URLRule qw/parse_rule apply_rule set_callback/;
use MyPlace::Curl;
use strict;
use Cwd;

BEGIN {
    use Exporter ();
    our ($VERSION,@ISA,@EXPORT,@EXPORT_OK,%EXPORT_TAGS);
    $VERSION        = 1.00;
    @ISA            = qw(Exporter);
    @EXPORT         = qw(
			$URLRULE_DIRECTORY
			&urlrule_process_data
			&urlrule_process_passdown
			&urlrule_process_args
			&urlrule_process_result
			&urlrule_do_action
			&urlrule_get_passdown
			urlrule_parse_pages
			&urlrule_set_callback
			urlrule_parse_rule
			urlrule_apply_rule
		);
}

#my $URLRULE_DIRECTORY = "$ENV{XR_PERL_SOURCE_DIR}/urlrule";

my %CALLBACK;

sub urlrule_set_callback {
    $CALLBACK{$_[0]}=$_[1];
}


sub make_url {
    my $line = shift;
    my $base = shift;
    if($line =~ /^([^\t]+)\t+(.+)$/) {
        return URI->new_abs($1,$base) . "\t" . $2;
    }
    else {
        return URI->new_abs($line,$base);
    }
}

sub build_url($$) {
    my ($base,$url) = @_;
    $url = URI->new_abs($url,$base) if($base);
    return $url;
}
sub strnum($$) {
    my $num=shift;
    my $len=shift;
    my $o_len = length($num);
    if(!$len or $len<=0 or $len<=$o_len) {
        return $num;
    }
    else {
        return "0" x ($len-$o_len) . $num;
    }
}

sub delete_dup {
    my %holder;
    foreach(@_) {
        $holder{$_} = 1;
    }
    return keys %holder;
}

sub change_directory {
    my $path = shift;
    return 1 unless($path);
    if(! -d $path) {
        app_prompt("Creating directory",$path);
        if(mkdir $path) {
            print STDERR "\t[OK]\n";
        }
        else {
            print STDERR "\t[Failed]\n";
            return undef;
        }
    }
    app_prompt("Changing directory",$path);
    if(chdir $path) {
        print STDERR "\t[OK]\n";
    }
    else {
        print STDERR "\t[Failed]\n";
        return undef;
    }
    return 1;
}

sub color_quote {
	my($pre,$text,$suf,$color,$reset) = @_;
	$pre="" unless($pre);
	$text="" unless($text);
	$suf="" unless($suf);
	$color="WHITE" unless($color);
	$reset="RESET" unless($reset);
	return color($reset) .  "$pre\"" . color($color) . $text . color($reset) . "\"$suf";
}

sub urlrule_do_action {
    my ($result_ref,$action,@args) = @_;
    return undef,"No results" unless(ref $result_ref);
    return undef,"No results" unless(%{$result_ref});
    my %result = %{$result_ref};
    my $msg="";
    $msg = "[" . $result{work_dir} . "]" if($result{work_dir});

    return undef,"No results" unless($result{data});
    if(ref $result{data} eq 'SCALAR') {
        $result{data} = [$result{data}];
    }
    app_prompt("Do Action",getcwd,"\n");
    my $file=$result{file};
    $file =~ s/\s*\w*[\/\\]\w*\s*//g if($file);
    my $pipeto=$action ? $action : $result{action};
    $pipeto = $pipeto ? $pipeto : $result{pipeto} ;
    if($file) {
        if (-f $file) {
            return undef,$msg . "Ingored (File exists)...";
        }
        else {
            open FO,">:utf8",$file or die("$!\n");
            print FO @{$result{data}};
            close FO;
            return 1,$msg . color_quote("Action File ",$file," OK.","YELLOW","CYAN");
        }
    }
    elsif($action and $action eq 'dump') {
        use Data::Dumper;
        local $Data::Dumper::Purity = 1; 
        print Data::Dumper->Dump([$result_ref],qw/*result_ref/);
        return 1, $msg . "Action DUMP OK.";
    }
    elsif($pipeto) {
        $pipeto .= ' "' . join('" "',@args) . '"' if(@args);
        open FO,"|-",$pipeto;
        foreach my $line (@{$result{data}}) {
            $line = &make_url($line,$result{base}) if($result{base});
            print FO $line,"\n";
        }
        close FO;
        return 1,$msg . color_quote("Action Pipeto ",$pipeto," OK.","YELLOW","CYAN");
    }
    elsif($result{hook}) {
        my $index=0;
        foreach my $line(@{$result{data}}) {
            $index ++;
            my @msg = ref $line ? @{$line} : ($line);
            $line = &make_url($line,$result{base}) if($result{base});
            &process_data($line,\%result);
        }
        return 1,$msg . "Action Hook OK.";
    }
    else {
        foreach my $line(@{$result{data}}) {
            $line = &make_url($line,$result{base}) if($result{base});
            print $line,"\n";
        }
        return 1,$msg . "OK.";
    }
}

sub urlrule_get_passdown {
    my $rule_ref = shift;
    return unless(ref $rule_ref);
    return unless(%{$rule_ref});
    my $result_ref = shift;
    return unless(ref $result_ref);
    return unless(%{$result_ref});
    return unless($result_ref->{pass_data});
    my %rule = %{$rule_ref};
    my %result = %{$result_ref};
    my $level = defined $result{level} ? $result{level} : $result{same_level} ? $rule{"level"} : $rule{"level"} - 1;
    my $action = $rule{"action"};
    my @args = $rule{"args"} ? @{$rule{"args"}} : ();
    if(ref $result{pass_data} eq 'SCALAR') {
        $result{pass_data} = [$result{pass_data}];
    }
    $result{pass_arg}="" unless($result{pass_arg});
    my @data;
    if($result{base}) {
        @data= map URI->new_abs($_,$result{base})->as_string,@{$result{pass_data}};
    }
    else {
        @data=@{$result{pass_data}};
    }
    my @subdirs;
    @subdirs=@{$result{pass_name}} if($result{pass_name});
    unless($result{no_subdir} and @subdirs) {
        my $len = length(@data);
        for(my $i=0;$i<@data;$i++) {
            push(@subdirs,strnum($i+1,$len));
        }
    }
    $level = $result{pass_level} if(exists $result{pass_level});
    my @ACTARG=($level,$action);
    unshift (@ACTARG,"domain:" . $result{pass_domain}) if($result{pass_domain});
    push @ACTARG,@args if(@args);
    my @actions;
    my $count=@data;
    for(my $i=0;$i<$count;$i++) {
        my @current;
        push @current, $result{no_subdir} ? undef : $subdirs[$i];
        push @current, $data[$i],@ACTARG;
        push @current, $result{pass_arg}->[$i] if($result{pass_arg});
        push @actions,\@current;
    }
    return $count,@actions;
}

sub callback_process_result {
    my $from = shift;
    app_prompt("Process result callback","$from\n") if($from);
    if($CALLBACK{process_result}) {
        &{$CALLBACK{process_result}}(@_);
    }
    else {
        goto &urlrule_process_result;
    }
}

sub callback_process_data {
    my $from = shift;
    app_prompt("Process data callback","$from\n") if($from);
    if($CALLBACK{process_data}) {
        &{$CALLBACK{process_data}}(@_);
    }
    else {
        goto &urlrule_process_data;
    }
}
sub callback_process_passdown {
    my $from = shift;
    app_prompt("Process passdown callback","$from\n") if($from);
    if($CALLBACK{process_passdown}) {
        &{$CALLBACK{process_passdown}}(@_);
    }
    else {
        goto &urlrule_process_passdown;
    }
}
sub callback_do_action {
    my $from = shift;
    app_prompt("Callback","$from\n") if($from);
    if($CALLBACK{process_do_action}) {
        &{$CALLBACK{process_do_action}}(@_);
    }
    else {
        goto &urlrule_do_action;
    }
}

sub urlrule_process_data {
    my $rule_ref = shift;
    return unless(ref $rule_ref);
    return unless(%{$rule_ref});
    my $result_ref = shift;
    return unless(ref $result_ref);
    return unless(%{$result_ref});

    return unless($result_ref->{data});
    my %rule = %{$rule_ref};
    my %result = %{$result_ref};
    
    my $url=$rule{"url"};
    my $level = $rule{"level"};
    my $action = $rule{"action"};
    my @args = $rule{"args"} ? @{$rule{"args"}} : ();
    my $msghd = $result{work_dir} ? "[". $result{work_dir} . "]" : "";
    my $count = @{$result{data}};
    app_prompt($msghd . "[Level $level]","Get data lines ",color('RED'),"$count\n");
    #,performing action $action..\n");
    my ($status,@message) = callback_do_action(undef,$result_ref,$action,@args);
    if($status) {
        app_prompt($msghd . "[Level $level]",@message,"\n");
        return 1;
    }
    else {
        app_prompt($msghd . "[Level $level]",color('READ'),@message,"\n");
        return undef;
    }
}


sub urlrule_process_passdown {
    my $rule_ref = shift;
    return unless(ref $rule_ref);
    return unless(%{$rule_ref});
    my $result_ref = shift;
    return unless(ref $result_ref);
    return unless(%{$result_ref});
    my $msghd="";
    my ($count,@passdown) = urlrule_get_passdown($rule_ref,$result_ref);
    my $level = $rule_ref->{level};
    if($count) {
        app_prompt($msghd . "[Level $level]" . "Get URLS to pass down",$count,"\n");
    }
    else {
        return undef;
        return 1;
    }
    my $CWD = getcwd;
    foreach(@passdown) {
        my($status1,$rule,$result) = urlrule_process_args(@{$_});
        if($status1)
        {
            my($status2,$pass_count,@pass_args)
                = urlrule_process_result($rule,$result);
            my $CWD = getcwd;
            if($status2) {
                foreach(@pass_args) {
                    callback_process_passdown(undef,@{$_});
                    chdir $CWD;
                }
            }
        }
        chdir $CWD;
    }
    return 1;
}
sub urlrule_process_result
{
    #return #status,pass_count,@pass_args;
    my($rule,$result,$p_action,@p_args) = @_;
    unless($rule and ref $rule and %{$rule})
    {
        app_error("Invaild Rule\n");
        return undef;
    }
    my $level = $rule->{"level"};
    unless($result and ref $result and %{$result})
    {
        app_error("Level $level>>","Invalid Result\n");
        return undef;
    }
    if($result->{work_dir}) {
        change_directory($result->{work_dir})
            or return undef;
    }
    my $action;
    my @args;
    if($p_action) 
    {
        $action = $p_action;
        @args = @p_args;
    }
    else
    {
        $action = $rule->{action};
        @args = @{$rule->{args}} if($rule->{args});
    }
    my $count = $result->{data} ? @{$result->{data}} : 0;
        app_prompt("[Level $level]" . "Get data Lines",color('RED'),"$count\n");
        my($action_status,$action_message) = callback_do_action(undef,$result,$action,@args);
        if($action_status) {
            app_prompt "[Level $level]","$action_message\n";
        }
        else {
            app_prompt "[Level $level]",color('YELLOW'),"$action_message\n" if($action_message);
        }
    my ($pass_count,@pass_args) = urlrule_get_passdown($rule,$result);
    app_prompt "[Level $level]" .  "Get URLs rules to pass down","$pass_count\n" if($pass_count);
    return 1,$pass_count,@pass_args;
}


sub urlrule_apply_rule {
	goto &apply_rule;
}

sub urlrule_parse_rule {
	goto &parse_rule;
}

sub urlrule_process_args 
{
    my ($dir,@args) = @_;
    my $rule = &parse_rule(@args);
    unless($rule)
    {
        app_message("Invalid args : " . join(" ",@args),"\n");
        return undef;
    }
	else {
		app_prompt("URL",$rule->{url},"\n");
		app_prompt("Source",$rule->{source},"\n");
	}
    my $level = $rule->{level};
    if($dir)
    {
        change_directory($dir) or return undef;
    }
    my ($status,$result) = &MyPlace::URLRule::apply_rule($rule);
	if(!$status) {
		app_error($result,"\n");
		return undef,undef,undef;
	}
    return 1,$rule,$result;
}

sub execute_rule {
    my $result = &MyPlace::URLRule::apply_rule(@_);
    return 1,$result;
}

MyPlace::URLRule::set_callback(
	'apply_rule',
	\&callback_process_data
);

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


