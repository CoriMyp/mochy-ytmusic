#!/usr/bin/perl
# checks manifest.json against the rules mochy's own parsers enforce (SkinParser.kt, SkinPlayerParser.kt, ModuleLooks.kt)
use strict;
use warnings;
use JSON::PP;
use File::Basename qw(dirname);

my $root = dirname(dirname($0));
chdir $root or die "cannot enter $root: $!";

my @errors;
my @warnings;
sub err { push @errors, $_[0] }
sub warn_ { push @warnings, $_[0] }

my $json = do { local $/; open my $fh, '<:raw', 'manifest.json' or die "no manifest.json: $!"; <$fh> };
my $m = eval { JSON::PP->new->utf8(1)->decode($json) };
die "manifest.json is not valid json: $@" unless $m;

# --- the schema, as the app reads it ---------------------------------------------------------
my %player_block = map { $_ => 1 } qw(cover title artist album text image box panel card path vector svg
    progress controls lyrics space row column stack visualizer button shape time shader);
my %page_block = map { $_ => 1 } qw(heading text image button divider space song playlist album artist
    search setting card box panel shader);
my %group = map { $_ => 1 } qw(box panel card row column stack);
my %button_action = map { $_ => 1 } qw(playpause play previous prev next like shuffle repeat lyrics menu customise customize close);
my %look_key = map { $_ => 1 } qw(playerStyle homeStyle playlistStyle thumbnailCornerRadius lyricsMotionStyle
    blurQuality blurStrengthPx enableProgressiveBlur elementBlur pureBlack accentColor dynamicTheme
    playerBackground flagshipBackground ipodTheme ipodWheelColor bottomBar);
my %look_values = (
    playerStyle        => [qw(FLAGSHIP CLASSIC TURNTABLE VIDEO IPOD POSTER TIMELINE LYRICS BEDSIDE BEDSIDE_TILES MODULE)],
    homeStyle          => [qw(MOCHYY LISTEN_NOW HOP_IN)],
    playlistStyle      => [qw(FLOW CLASSIC MINIMAL)],
    lyricsMotionStyle  => [qw(MOTION LEGACY BORING PLAIN)],
    blurQuality        => [qw(LOW HIGH)],
    bottomBar          => [qw(FROSTED MODULE)],
    playerBackground   => [qw(AMBIENT APPLE_MUSIC COVER_GRADIENT DARK_GRADIENT SOLID)],
    flagshipBackground => [qw(AMBIENT APPLE_MUSIC COVER_GRADIENT DARK_GRADIENT SOLID)],
    ipodTheme          => [qw(SILVER BLACK U2 TRUE_DARK)],
    ipodWheelColor     => [qw(THEME WHITE BLACK RED)],
);
my %builtin_condition = map { $_ => 1 } qw(@playing @paused @liked @shuffle @repeat @lyrics @landscape);

# --- what a zip may bring --------------------------------------------------------------------
my %settings;
for my $s (@{ $m->{settings} || [] }) {
    my $key = $s->{key} // '';
    err("setting without a key") unless length $key;
    err("setting $key appears twice") if $settings{$key};
    $settings{$key} = $s;
    my $type = $s->{type} // 'select';
    if ($type eq 'select') {
        my @opt = @{ $s->{options} || [] };
        err("setting $key is a select with no options") unless @opt;
        my %seen;
        for my $o (@opt) {
            err("setting $key has an option without a value") unless defined $o->{value};
            err("setting $key option $o->{value} appears twice") if $seen{ $o->{value} }++;
        }
        if (defined $s->{default}) {
            err("setting $key default $s->{default} is not one of its options") unless grep { $_->{value} eq $s->{default} } @opt;
        }
    } elsif ($type eq 'toggle') {
        if (defined $s->{default}) { err("setting $key default must be \"true\" or \"false\"") unless $s->{default} =~ /^(true|false)$/ }
    } elsif ($type eq 'text') {
        # anything goes
    } else {
        err("setting $key has an unknown type $type");
    }
}

# --- every file the manifest names has to be in the zip ---------------------------------------
my %files = map { $_ => 1 } qw(manifest.json icon.png banner.png);
my @paths;
my $collect;
$collect = sub {
    my ($node) = @_;
    return unless ref $node;
    if (ref $node eq 'HASH') {
        for my $k (qw(icon banner image imageOn frame shader)) {
            push @paths, $node->{$k} if defined $node->{$k} && !ref $node->{$k} && $node->{$k} !~ m{^https?://};
        }
        if (ref $node->{font} eq 'HASH') { push @paths, grep { defined } @{ $node->{font} }{qw(regular bold)} }
        $collect->($_) for values %$node;
    } elsif (ref $node eq 'ARRAY') {
        $collect->($_) for @$node;
    }
};
$collect->($m);
for my $p (@paths) {
    err("file $p is named in the manifest but is not in the zip") unless $files{$p} || -f $p;
}

# --- look -----------------------------------------------------------------------------------
sub check_look {
    my ($look, $where) = @_;
    return unless ref $look eq 'HASH';
    for my $k (sort keys %$look) {
        unless ($look_key{$k}) { err("$where sets $k, which is not a look setting"); next }
        my $v = $look->{$k};
        if (my $allowed = $look_values{$k}) {
            err("$where sets $k to $v, which is not one of @$allowed") unless grep { $_ eq uc $v } @$allowed;
        } elsif ($k eq 'accentColor') {
            err("$where sets accentColor to $v, which is not #RRGGBB") unless $v =~ /^#[0-9a-fA-F]{6}$/;
        } elsif ($k eq 'thumbnailCornerRadius') {
            err("$where sets thumbnailCornerRadius outside 0 to 45") unless $v =~ /^\d+$/ && $v <= 45;
        } elsif ($k eq 'blurStrengthPx') {
            err("$where sets blurStrengthPx outside 10 to 50") unless $v =~ /^\d+$/ && $v >= 10 && $v <= 50;
        } elsif ($v ne 'true' && $v ne 'false') {
            err("$where sets $k to $v, which is not true or false");
        }
    }
}
check_look($m->{look}, 'the module look');
for my $key (sort keys %settings) {
    for my $o (@{ $settings{$key}{options} || [] }) {
        check_look($o->{look}, "an option of $key");
        err("an option of $key carries a glass, but this module brings no bar shader") if $o->{glass};
    }
    check_look($settings{$key}{look}, "setting $key");
}

# --- settings and blocks --------------------------------------------------------------------
sub check_condition {
    my ($cond, $where) = @_;
    return unless defined $cond;
    my $bare = $cond;
    $bare =~ s/^!//;
    return if $builtin_condition{$bare};
    return if $bare =~ /^[a-z0-9_-]+$/ && $settings{$bare};
    $bare =~ /^([a-z0-9_-]+)[!=]/ and $settings{$1} and return;
    err("$where uses the condition \"$cond\", which is neither a built-in nor one of this module's settings");
}

my %seen_keyframes;
my $player = $m->{player};
if (ref $player eq 'HASH') {
    %seen_keyframes = map { $_ => 1 } keys %{ $player->{keyframes} || {} };
    err("the player brings more than 40 blocks") if @{ $player->{blocks} || [] } > 40;
    err("the player brings more than 8 header blocks") if @{ $player->{header} || [] } > 8;
    err("the player brings more than 4 keyframe sets") if keys %seen_keyframes > 24;
    for my $k (@{ ref $player->{customise} eq 'HASH' ? ($player->{customise}{settings} || []) : ($player->{customise} || []) }) {
        err("the customise sheet offers $k, which is not one of this module's settings") unless $settings{$k};
    }
    err("the player brings more than 4 menu items") if @{ $player->{menu} || [] } > 4;
    for my $item (@{ $player->{menu} || [] }) {
        err("a menu item has no title") unless length($item->{title} // '');
        err("a menu title is over 30 characters") if length($item->{title} // '') > 30;
        my @t = grep { defined $item->{$_} } qw(link page search action);
        err("a menu item needs exactly one of link, page, search or action") unless @t == 1;
        err("menu link $item->{link} is not https") if $item->{link} && $item->{link} !~ m{^https?://};
    }
    my $walk;
    $walk = sub {
        my ($blocks, $depth, $where) = @_;
        err("$where nests deeper than four groups") if $depth > 4;
        for my $b (@$blocks) {
            err("$where has a block that is not an object") and next unless ref $b eq 'HASH';
            my $type = lc($b->{type} // '');
            unless ($player_block{$type}) { err("$where has a block of type \"$type\", which mochy doesn't know"); next }
            check_condition($b->{when}, "the $type block") if defined $b->{when};
            if (ref $b->{states} eq 'HASH') {
                check_condition($_, "a state of the $type block") for keys %{ $b->{states} };
            } elsif (ref $b->{states} eq 'ARRAY') {
                check_condition($_->{when}, "a state of the $type block") for @{ $b->{states} };
            }
            if ($type eq 'button') {
                if (defined $b->{action}) {
                    err("the button action \"$b->{action}\" is not one mochy knows") unless $button_action{ lc $b->{action} };
                }
                my @t = grep { defined $b->{$_} } qw(link page search);
                err("a button needs an action or exactly one of link, page, search") unless $b->{action} || @t == 1;
                err("button link $b->{link} is not https") if $b->{link} && $b->{link} !~ m{^https?://};
            }
            if ($type eq 'path' || $type eq 'vector' || $type eq 'svg') {
                err("a path block has no d") unless length($b->{d} // '');
                err("a path block's d is over 8000 characters") if length($b->{d} // '') > 8000;
                err("a path block's d has characters svg paths don't use") if ($b->{d} // '') =~ /[^MmLlHhVvCcSsQqTtAaZz0-9eE.,+\-\s]/;
            }
            if (ref $b->{animate} eq 'HASH' && defined $b->{animate}{keyframes} && !ref $b->{animate}{keyframes}) {
                err("a block animates with \"$b->{animate}{keyframes}\", which the player never names") unless $seen_keyframes{ $b->{animate}{keyframes} };
            }
            if (ref $b->{enter} eq 'HASH' && defined $b->{enter}{keyframes} && !ref $b->{enter}{keyframes}) {
                err("a block enters with \"$b->{enter}{keyframes}\", which the player never names") unless $seen_keyframes{ $b->{enter}{keyframes} };
            }
            if (ref $b->{on} eq 'HASH') {
                for my $ev (keys %{ $b->{on} }) {
                    my $v = $b->{on}{$ev};
                    if (!ref $v && defined $v) {
                        err("an event animation on $ev names \"$v\", which the player never names") unless $seen_keyframes{$v};
                    } elsif (ref $v eq 'HASH' && defined $v->{keyframes} && !ref $v->{keyframes}) {
                        err("an event animation on $ev names \"$v->{keyframes}\", which the player never names") unless $seen_keyframes{ $v->{keyframes} };
                    }
                }
            }
            if (ref $b->{colors} eq 'ARRAY' && @{ $b->{colors} } > 6) { err("a $type block has more than 6 colours") }
            if ($group{$type} && $b->{blocks}) { $walk->($b->{blocks}, $depth + 1, "the $type block") }
            for my $c (grep { defined $b->{$_} } qw(color fill track active tint strokeColor image)) {
                my $v = $b->{$c};
                next if ref $v;
                if ($v =~ /^\$([a-z0-9_-]+)/) {
                    err("the $type block colours with \$$1, which is not one of this module's settings") unless $settings{$1};
                }
            }
            if (defined $b->{text} && !ref $b->{text}) {
                while ($b->{text} =~ /\{\$([a-z0-9_-]+)\}/g) {
                    err("a $type block writes {\$$1}, which is not one of this module's settings") unless $settings{$1};
                }
            }
        }
    };
    $walk->($player->{blocks} || [], 0, 'the player');
    $walk->($player->{header} || [], 1, 'the header');
} else {
    err("the manifest has no player");
}

# --- pages ----------------------------------------------------------------------------------
my %page_id;
for my $page (@{ $m->{pages} || [] }) {
    my $id = $page->{id} // '';
    err("page id \"$id\" must be a-z, 0-9, - or _ and up to 40") unless $id =~ /^[a-z0-9_-]{1,40}$/;
    err("page $id appears twice") if $page_id{$id}++;
    my @blocks = @{ $page->{blocks} || [] };
    err("page $id brings no blocks") unless @blocks;
    err("page $id brings more than 80 blocks") if @blocks > 80;
    for my $b (@blocks) {
        my $type = lc($b->{type} // '');
        unless ($page_block{$type}) { err("page $id has a block of type \"$type\", which mochy doesn't know"); next }
        if ($type eq 'setting') {
            err("page $id shows setting $b->{key}, which this module doesn't have") unless $settings{ $b->{key} // '' };
        }
        if ($type eq 'button') {
            err("page $id has a button with no text") unless defined $b->{text};
            err("page $id has a button to $b->{link}, which is not a web link") unless ($b->{link} // '') =~ m{^https?://};
        }
        if ($type eq 'search') {
            err("page $id has a search block without a query") unless defined $b->{query};
        }
        if ($type eq 'card' || $type eq 'box' || $type eq 'panel') {
            err("page $id nests a card inside a card") if grep { ($_->{type} // '') =~ /^(card|box|panel)$/ } @{ $b->{blocks} || [] };
            for my $inner (@{ $b->{blocks} || [] }) {
                next unless lc($inner->{type} // '') eq 'setting';
                err("page $id shows setting $inner->{key}, which this module doesn't have") unless $settings{ $inner->{key} // '' };
            }
        }
        if (defined $b->{image}) { err("page $id shows $b->{image}, which is not in the zip") unless -f $b->{image} || $b->{image} =~ m{^https?://} }
    }
}

# --- menu rows ------------------------------------------------------------------------------
err("the module brings more than 6 menu rows") if @{ $m->{actions} || [] } > 6;
for my $a (@{ $m->{actions} || [] }) {
    err("a menu row has no title") unless length($a->{title} // '');
    err("a menu row title is over 40 characters") if length($a->{title} // '') > 40;
    my @t = grep { defined $a->{$_} } qw(link page search);
    err("a menu row needs exactly one of link, page, search") unless @t == 1;
    err("menu row $a->{title} opens page $a->{page}, which the module doesn't bring") if $a->{page} && !$page_id{ $a->{page} };
    err("menu row $a->{title} links to $a->{link}, which is not a web link") if $a->{link} && $a->{link} !~ m{^https?://};
}

# --- the manifest decides what kind of module it is ------------------------------------------
my $adds_something = $m->{look} || $m->{player} || $m->{glass} || $m->{font} || @{ $m->{pages} || [] } || @{ $m->{actions} || [] };
err("the manifest adds nothing, so mochy would read it as a song source") unless $adds_something;

for my $w (@warnings) { print "note: $w\n" }
if (@errors) {
    print "FAILED\n";
    print " - $_\n" for @errors;
    exit 1;
}
printf "manifest ok: %d settings, %d player blocks, %d pages, %d menu rows\n",
    scalar(keys %settings), scalar @{ $m->{player}{blocks} || [] }, scalar @{ $m->{pages} || [] }, scalar @{ $m->{actions} || [] };
