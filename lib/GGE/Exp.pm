use v6;
use GGE::Match;

class CodeString {
    has Str $!contents = '';
    my $counter = 0;

    method emit($string, *@args, *%kwargs) {
        $!contents ~= $string\
                        .subst(/\%(\d)/, {   @args[$0] // '...' }, :g)\
                        .subst(/\%(\w)/, { %kwargs{$0} // '...' }, :g); 
    }

    method escape($string) {
        q['] ~ $string.trans( [ q['], q[\\] ] => [ q[\\'], q[\\\\] ] ) ~ q['];
    }

    method unique($prefix = '') {
        $prefix ~ $counter++
    }

    method Str { $!contents }
}

# a GGE::Exp describing what it contains, most commonly its .ast property,
# but sometimes other things.
role GGE::ShowContents {
    method contents() {
        self.ast;
    }
}

# RAKUDO: Could name this one GGE::Exp::CUT or something, if enums
#         with '::' in them worked, which they don't. [perl #71460]
enum CUT (
    CUT_GROUP => -1,
    CUT_RULE  => -2,
    CUT_MATCH => -3,
);

class GGE::Exp is GGE::Match {
    my $group;

    method structure($indent = 0) {
        # RAKUDO: The below was originally written as a map, but there's
        #         a bug somewhere in &map and lexical pads. The workaround
        #         is to write it as a for loop.
        my $inside = '';
        if self.llist {
            for self.llist {
                $inside ~= "\n" ~ $_.structure($indent + 1);
            }
            $inside = "[$inside\n" ~ '  ' x $indent ~ ']';
        }
        my $contents = '';
        if defined self.?contents {
            $contents = " ('{self.contents}') ";
        }
        $contents ~= $inside;
        '  ' x $indent ~ self.WHAT.perl.subst(/^.*':'/, '') ~ $contents;
    }

    method compile(:$debug) {
        my $source = self.root-p6(:$debug);
        if $debug {
            say $source;
            say '';
        }
        my $binary = eval $source
            or die ~$!;
        return $binary;
    }

    method reduce() {
        self;
    }

    method root-p6(:$debug) {
        my $code = CodeString.new();
        $code.unique(); # XXX: Remove this one when we do other real calls
        $code.emit( q[[sub ($target, :$debug) {
    my $mob = GGE::Match.new(:$target);
    my $mfrom;
    my $cpos = 0;
    my $pos;
    my $rep;
    my $lastpos = $target.chars;
    my $cutmark;
    my @gpad;             # TODO: PGE generates this one only when needed
    my @ustack;           # TODO: PGE generates this one only when needed
    my $captscope = $mob; # TODO: PGE generates this one only when needed
    my $captob;           # TODO: PGE generates this one only when needed
    my @cstack = 'try_match';
    my &goto = -> $label { @cstack[*-1] = $label };
    my &local-branch = -> $label {
        @cstack[*-1] ~= '_cont';
        @cstack.push($label)
    };
    my &local-return = -> { @cstack.pop };
    loop {
        given @cstack[*-1] {
            when 'try_match' {
                if $cpos > $lastpos { goto('fail_rule'); break; }
                $mfrom = $pos = $cpos;
                $cutmark = 0;
                local-branch('R');
            }
            when 'try_match_cont' {
                if $cutmark <= %0 { goto('fail_cut'); break; }
                ++$cpos;
                goto('try_match');
            }
            when 'fail_rule' {
                # $cutmark = %0 # XXX: Not needed yet
                goto('fail_cut');
            }
            when 'fail_cut' {
                $mob.from = 0;
                $mob.to = -2;
                return $mob;
            }
            when 'succeed' {
                $mob.from = $mfrom;
                $mob.to = $pos;
                return $mob;
            }
            when 'fail' {
                local-return();
            } ]], CUT_RULE);
        my $explabel = 'R';
        $GGE::Exp::group = self;
        my $exp = self.reduce;
        if $debug {
            say $exp.structure;
            say '';
        }
        $exp.p6($code, $explabel, 'succeed');
        $code.emit( q[[
            default {
                die "No such label: {@cstack[*-1]}";
            }
        }
    }
} ]]);
    }

    method getargs($label, $next, %hash?) {
        %hash<L S> = $label, $next;
        if %hash.exists('quant') {
            my $quant = %hash<quant>;
            %hash<m> = $quant.hash-access('min');
            %hash<M> = %hash<m> == 0   ?? '### ' !! '';
            %hash<n> = $quant.hash-access('max');
            %hash<N> = %hash<n> == Inf ?? '### ' !! '';
            my $bt = $quant.hash-access('backtrack').name.lc;
            %hash<Q> = sprintf '%s..%s (%s)', %hash<m>, %hash<n>, $bt;
        }
        return %hash;
    }

    method gencapture($label) {
        my $cname = self.hash-access('cname');
        my $captgen  = CodeString.new;
        my $captsave = CodeString.new;
        my $captback = CodeString.new;
        my $indexing = $cname.substr(0, 1) eq q[']
                        ?? "\$captscope.hash-access($cname)"
                        !! "\$captscope[$cname]";
        if self.hash-access('iscapture') {
            if self.hash-access('isarray') {
                $captsave.emit('%0.push($captob);', $indexing);
                $captback.emit('%0.pop();', $indexing);
                $captgen.emit( q[[if defined %0 {
                    goto('%1_cgen');
                    break;
                }
                %0 = [];
                local-branch('%1_cgen');
            }
            when '%1_cont' {
                %0 = undef;
                goto('fail');
            }
            when '%1_cgen' { ]], $indexing, $label);
            }
            else {
                $captsave.emit('%0 = $captob;', $indexing);
                if $cname.substr(0, 1) eq q['] {
                    $captback.emit('$captscope.delete(%0);', $cname);
                }
                else {
                    $captback.emit('%0 = undef;', $indexing);
                }
            }
        }
        # RAKUDO: Cannot do multiple returns yet.
        return ($captgen, $captsave, $captback);
    }
}

class GGE::Exp::Literal is GGE::Exp does GGE::ShowContents {
    method p6($code, $label, $next) {
        my %args = self.getargs($label, $next);
        my $literal = self.ast;
        my $litlen = $literal.chars;
        %args<I> = '';
        if self.hash-access('ignorecase') {
            %args<I> = '.lc';
            $literal .= lc;
        }
        $literal = $code.escape($literal);
        $code.emit( q[
            when '%L' {
                if $pos + %0 > $lastpos
                   || $target.substr($pos, %0)%I ne %1 {
                    goto('fail');
                    break;
                }
                $pos += %0;
                goto('%S');
            } ], $litlen, $literal, |%args);
    }
}

enum GGE_BACKTRACK <
    GREEDY
    EAGER
    NONE
>;

class GGE::Exp::Quant is GGE::Exp {
    method contents() {
        my ($min, $max, $bt) = map { self.hash-access($_) },
                                   <min max backtrack>;
        $bt //= GREEDY;
        "{$bt.name.lc} $min..$max"
    }

    method p6($code, $label, $next) {
        my %args = self.getargs($label, $next, { quant => self });
        my $replabel = $label ~ '_repeat';
        my $nextlabel = $code.unique('R');
        %args<c C> = 0, '### ';
        given self.hash-access('backtrack') {
            when EAGER {
                $code.emit( q[[
            when '%L' { # quant %Q eager
                push @gpad, 0;
                local-branch('%0');
            }
            when '%L_cont' {
                pop @gpad;
                goto('fail');
            }
            when '%0' {
                $rep = @gpad[*-1];
                %Mif $rep < %m { goto('%L_1'); break; }
                pop @gpad;
                push @ustack, $pos;
                push @ustack, $rep;
                local-branch('%S');
            }
            when '%0_cont' {
                $rep = pop @ustack;
                $pos = pop @ustack;
                push @gpad, $rep;
                goto('%L_1');
            }
            when '%L_1' {
                %Nif $rep >= %n { goto('fail'); break; }
                ++$rep;
                @gpad[*-1] = $rep;
                goto('%1');
            } ]], $replabel, $nextlabel, |%args);
            }
            when NONE {
                %args<c C> = $code.unique(), '';
                if self.hash-access('min') != 0
                   || self.hash-access('max') != Inf {
                    continue;
                }
                $code.emit( q[[
            when '%L' { # quant 0..Inf none
                local-branch('%0');
            }
            when '%L_cont' {
                if $cutmark != %c { goto('fail'); break; }
                $cutmark = 0;
                goto('fail');
            }
            when '%0' {
                push @ustack, $pos;
                local-branch('%1');
            }
            when '%0_cont' {
                $pos = pop @ustack;
                if $cutmark != 0 { goto('fail'); break; }
                local-branch('%S');
            }
            when '%0_cont_cont' {
                if $cutmark != 0 { goto('fail'); break; }
                $cutmark = %c;
                goto('fail');
            } ]], $replabel, $nextlabel, |%args);
            }
            default {
                $code.emit( q[[
            when '%L' { # quant %Q greedy/none
                push @gpad, 0;
                local-branch('%0');
            }
            when '%L_cont' {
                pop @gpad;
                %Cif $cutmark != %c { goto('fail'); break; }
                %C$cutmark = 0;
                goto('fail');
            }
            when '%0' {
                $rep = @gpad[*-1];
                %Nif $rep >= %n { goto('%L_1'); break; }
                ++$rep;
                @gpad[*-1] = $rep;
                push @ustack, $pos;
                push @ustack, $rep;
                local-branch('%1');
            }
            when '%0_cont' {
                $rep = pop @ustack;
                $pos = pop @ustack;
                if $cutmark != 0 { goto('fail'); break; }
                --$rep;
                goto('%L_1');
            }
            when '%L_1' {
                %Mif $rep < %m { goto('fail'); break; }
                pop @gpad;
                push @ustack, $rep;
                local-branch('%S');
            }
            when '%L_1_cont' {
                $rep = pop @ustack;
                push @gpad, $rep;
                if $cutmark != 0 { goto('fail'); break; }
                %C$cutmark = %c;
                goto('fail');
            } ]], $replabel, $nextlabel, |%args);
            }
        }
        self[0].p6($code, $nextlabel, $replabel);
    }
}

class GGE::Exp::CCShortcut is GGE::Exp does GGE::ShowContents {
    method p6($code, $label, $next) {
        my $failcond = self.ast eq '.'
                       ?? 'False'
                       !! sprintf '$target.substr($pos, 1) !~~ /%s/', self.ast;
        $code.emit( q[
            when '%0' { # ccshortcut %1
                if $pos >= $lastpos || %2 {
                    goto('fail');
                    break;
                }
                ++$pos;
                goto('%3');
            } ], $label, self.ast, $failcond, $next );
    }
}

class GGE::Exp::Newline is GGE::Exp does GGE::ShowContents {
    method p6($code, $label, $next) {
        $code.emit( q[
            when '%0' { # newline
                unless $target.substr($pos, 1) eq "\n"|"\r" {
                    goto('fail');
                    break;
                }
                my $twochars = $target.substr($pos, 2);
                ++$pos;
                if $twochars eq "\r\n" {
                    ++$pos;
                }
                goto('%1');
            } ], $label, $next);
    }
}

class GGE::Exp::Anchor is GGE::Exp does GGE::ShowContents {
    method p6($code, $label, $next) {
        $code.emit( q[
            when '%0' { # anchor %1 ], $label, self.ast );
        given self.ast {
            when '^' {
                $code.emit( q[
                if $pos == 0 { goto('%0'); break; }
                goto('fail'); ], $next );
            }
            when '$' {
                $code.emit( q[
                if $pos == $lastpos { goto('%0'); break; }
                goto('fail'); ], $next );
            }
            when '<<' {
                $code.emit( q[
                if $target.substr($pos, 1) ~~ /\w/
                   && ($pos == 0 || $target.substr($pos - 1, 1) !~~ /\w/) {
                    goto('%0');
                    break;
                }
                goto('fail'); ], $next );
            }
            when '>>' {
                $code.emit( q[
                if $pos > 0 && $target.substr($pos - 1, 1) ~~ /\w/
                   && ($pos == $lastpos || $target.substr($pos, 1) !~~ /\w/) {
                    goto('%0');
                    break;
                }
                goto('fail'); ], $next );
            }
            when '^^' {
                $code.emit( q[
                if $pos == 0 || $pos < $lastpos
                                && $target.substr($pos - 1, 1) eq "\n" {
                    goto('%0');
                    break;
                }
                goto('fail'); ], $next );
            }
            when '$$' {
                $code.emit( q[
                if $target.substr($pos, 1) eq "\n"
                   || $pos == $lastpos
                      && ($pos < 1 || $target.substr($pos - 1, 1) ne "\n") {
                    goto('%0');
                    break;
                }
                goto('fail'); ], $next );
            }
        }
        $code.emit( q[
            } ]);
    }
}

class GGE::Exp::Concat is GGE::Exp {
    method reduce() {
        my $n = self.elems;
        my @old-children = self.llist;
        self.clear;
        for @old-children -> $old-child {
            my $new-child = $old-child.reduce();
            self.push($new-child);
        }
        return self.llist == 1 ?? self[0] !! self;
    }

    method p6($code, $label, $next) {
        $code.emit( q[
            # concat ]);
        my $cl = $label;
        my $nl;
        my $end = self.llist.elems - 1;
        for self.llist.kv -> $i, $child {
            $nl = $i == $end ?? $next !! $code.unique('R');
            $child.p6($code, $cl, $nl);
            $cl = $nl;
        }
    }
}

class GGE::Exp::Modifier   is GGE::Exp does GGE::ShowContents {
    method contents() {
        self.hash-access('key');
    }

    method start($, $, %) { DESCEND }
}

class GGE::Exp::EnumCharList is GGE::Exp does GGE::ShowContents {
    method contents() {
        my $prefix = '';
        if self.hash-access('isnegated') {
            $prefix = '-';
            if self.hash-access('iszerowidth') {
                $prefix = '!';
            }
        }
        my $list = self.ast;
        qq[<$prefix\[$list\]>]
    }

    method p6($code, $label, $next) {
        my $test = self.hash-access('isnegated') ?? 'defined' !! '!defined';
        my $charlist = $code.escape(self.ast);
        $code.emit( q[
            when '%0' {
                if $pos >= $lastpos
                   || %1 %2.index($target.substr($pos, 1)) {
                    goto('fail');
                    break;
                }
                ++$pos;
                goto('%3');
            } ], $label, $test, $charlist, $next);
    }
}

class GGE::Exp::Alt is GGE::Exp {
    method reduce() {
        self[0] .= reduce;
        self[1] .= reduce;
        return self;
    }

    method p6($code, $label, $next) {
        my $exp0label = $code.unique('R');
        my $exp1label = $code.unique('R');
        $code.emit( q[
            when '%0' { # alt %1, %2
                push @ustack, $pos;
                local-branch('%1');
            }
            when '%0_cont' {
                $pos = pop @ustack;
                if $cutmark != 0 { goto('fail'); break; }
                goto('%2');
            } ], $label, $exp0label, $exp1label);
        self[0].p6($code, $exp0label, $next);
        self[1].p6($code, $exp1label, $next);
    }
}

class GGE::Exp::Conj is GGE::Exp {
    method reduce() {
        self[0] .= reduce;
        self[1] .= reduce;
        return self;
    }

    method p6($code, $label, $next) {
        my $exp0label = $code.unique('R');
        my $exp1label = $code.unique('R');
        my $chk0label = $label ~ '_chk0';
        my $chk1label = $label ~ '_chk1';
        $code.emit( q[[
            when '%0' { # conj %1, %2
                push @gpad, $pos, $pos;
                local-branch('%1');
            }
            when '%0_cont' {
                pop @gpad;
                pop @gpad;
                goto('fail');
            }
            when '%3' {
                @gpad[*-1] = $pos;
                $pos = @gpad[*-2];
                goto('%2');
            }
            when '%4' {
                if $pos != @gpad[*-1] {
                    goto('fail');
                    break;
                }
                my $p1 = pop @gpad;
                my $p2 = pop @gpad;
                push @ustack, $p2, $p1;
                local-branch('%5');
            }
            when '%4_cont' {
                my $p1 = pop @ustack;
                my $p2 = pop @ustack;
                push @gpad, $p2, $p1;
                goto('fail');
            } ]], $label, $exp0label, $exp1label, $chk0label, $chk1label,
                  $next);
        self[0].p6($code, $exp0label, $chk0label);
        self[1].p6($code, $exp1label, $chk1label);
    }
}

class GGE::Exp::Group is GGE::Exp {
    method reduce() {
        my $group = $GGE::Exp::group;
        $GGE::Exp::group = self;
        self[0] .= reduce;
        $GGE::Exp::group = $group;
        return self.exists('cutmark') && self.hash-access('cutmark') > 0
            || self.exists('iscapture') && self.hash-access('iscapture') != 0
                ?? self
                !! self[0];
    }

    method p6($code, $label, $next) {
        self[0].p6($code, $label, $next);
    }
}

class GGE::Exp::CGroup is GGE::Exp::Group {
    method p6($code, $label, $next) {
        my $explabel = $code.unique('R');
        my $expnext = $label ~ '_close';
        my %args = self.getargs($label, $next);
        my ($captgen, $captsave, $captback) = self.gencapture($label);
        %args<c C> = self.hash-access('cutmark'), '### ';
        %args<X> = self.hash-access('isscope') ?? '' !! '### ';
        $code.emit( q[[
            when '%L' { # capture
                %0
                goto('%L_1');
            }
            when '%L_1' {
                $captob = $captscope.new($captscope);
                $captob.from = $pos; # XXX: PGE uses .pos here somehow.
                push @gpad, $captscope;
                push @gpad, $captob;
                %X$captscope = $captob;
                local-branch('%E');
            }
            when '%L_1_cont' {
                $captob = pop @gpad;
                $captscope = pop @gpad;
                %Cif $cutmark != %c { goto('fail'); break; }
                %C$cutmark = 0;
                goto('fail');
            }
            when '%L_close' {
                push @ustack, $captscope;
                $captob = pop @gpad;
                $captscope = pop @gpad;
                $captob.to = $pos;
                %1
                push @ustack, $captob;
                local-branch('%S');
            }
            when '%L_close_cont' {
                $captob = pop @ustack;
                %2
                push @gpad, $captscope;
                push @gpad, $captob;
                $captscope = pop @ustack;
                goto('fail');
            } ]], $captgen, $captsave, $captback, :E($explabel), |%args);
        self[0].p6($code, $explabel, $expnext);
    }
}

class GGE::Exp::Cut is GGE::Exp {
    method reduce() {
        if self.hash-access('cutmark') > CUT_RULE {
            my $group = $GGE::Exp::group;
            if !$group.hash-access('cutmark') {
                $group.hash-access('cutmark') = CodeString.unique();
            }
            self.hash-access('cutmark') = $group.hash-access('cutmark');
        }
        return self;
    }

    method p6($code, $label, $next) {
        my $cutmark = self.hash-access('cutmark') // 'NO_CUTMARK';
        $code.emit( q[
            when '%0' { # cut %2
                local-branch('%1');
            }
            when '%0_cont' {
                $cutmark = %2;
                goto('fail');
            } ], $label, $next, $cutmark);
    }
}

class GGE::Exp::Scalar is GGE::Exp does GGE::ShowContents {
    method p6($code, $label, $next) {
        my $cname = self.hash-access('cname');
        my $C = $cname.substr(0, 1) eq q[']
                ?? '$mob.hash-access(' ~ $cname ~ ')'
                !! '$mob[' ~ $cname ~ ']';
        $code.emit( q[[
            when '%0' { # scalar %2
                my $capture = %C;
                if $capture ~~ Array {
                    $capture = $capture[*-1];
                }
                my $length = $capture.chars;
                if $pos + $length > $lastpos
                   || $target.substr($pos, $length) ne $capture {
                    goto('fail');
                    break;
                }
                $pos += $length;
                goto('%1');
            } ]], $label, $next, $cname, :$C);
        return;
    }
}

class GGE::Exp::Alias is GGE::Exp {
    method contents() {
        self.hash-access('cname');
    }
}

class GGE::Exp::Subrule is GGE::Exp does GGE::ShowContents {
    method p6($code, $label, $next) {
        my %args = self.getargs($label, $next);
        my $subname = self.hash-access('subname');
        my ($captgen, $captsave, $captback) = self.gencapture($label);
        $code.emit( q[[
            when '%L' {
                $captob = $captscope;
                $captob.to = $pos;
                unless $mob.can('%0') {
                    die "Unable to find regex '%0'";
                }
                $captob = $captob.%0(); ]], $subname, |%args);
        if self.hash-access('iszerowidth') {
            my $test = self.hash-access('isnegated') ?? 'unless' !! 'if';
            $code.emit( q[[
                # XXX: fail match
                %1 $captob.to < 0 { goto('fail'); break; }
                $captob.from = $captob.to = $pos;
                goto('%2');
            } ]], "XXX: fail match", $test, $next);
        }
        else {
            $code.emit( q[[
                # XXX: fail match
                if $captob.to < 0 { goto('fail'); break; }
                %2
                %3
                $captob.from = $pos; # XXX: No corresponding line in PGE
                $pos = $captob.to;
                local-branch('%1'); # XXX: PGE does backtracking into subrules
            }
            when '%L_cont' {
                %4
                goto('fail');
            } ]], CUT_MATCH, $next, $captgen, $captsave, $captback, |%args);
        }
    }
}
