use v6;
use GGE::Match;
use GGE::Exp;
use GGE::OPTable;
use GGE::Cursor;

class GGE::Perl6Regex {
    has $!regex;

    method new($pattern) {
        my $optable = GGE::OPTable.new();
        $optable.newtok('term:',     :precedence('='),
                        :parsed(&GGE::Perl6Regex::parse_term));
        $optable.newtok('term:#',    :equiv<term:>,
                        :parsed(&GGE::Perl6Regex::parse_term_ws));
        $optable.newtok('term:\\',   :equiv<term:>,
                        :parsed(&GGE::Perl6Regex::parse_term_backslash));
        $optable.newtok('term:^',    :equiv<term:>,
                        :match(GGE::Exp::Anchor));
        $optable.newtok('term:^^',   :equiv<term:>,
                        :match(GGE::Exp::Anchor));
        $optable.newtok('term:$',    :equiv<term:>, # XXX not per PGE
                        :match(GGE::Exp::Anchor));
        $optable.newtok('term:$$',   :equiv<term:>,
                        :match(GGE::Exp::Anchor));
        $optable.newtok('term:<<',   :equiv<term:>,
                        :match(GGE::Exp::Anchor));
        $optable.newtok('term:>>',   :equiv<term:>,
                        :match(GGE::Exp::Anchor));
        $optable.newtok('term:.',    :equiv<term:>,
                        :match(GGE::Exp::CCShortcut));
        $optable.newtok('term:\\s',  :equiv<term:>,
                        :match(GGE::Exp::CCShortcut));
        $optable.newtok('term:\\S',  :equiv<term:>,
                        :match(GGE::Exp::CCShortcut));
        $optable.newtok('term:\\w',  :equiv<term:>,
                        :match(GGE::Exp::CCShortcut));
        $optable.newtok('term:\\N',  :equiv<term:>,
                        :match(GGE::Exp::CCShortcut));
        $optable.newtok('term:\\n',  :equiv<term:>,
                        :match(GGE::Exp::Newline));
        $optable.newtok('term:<[',   :equiv<term:>,
                        :parsed(&GGE::Perl6Regex::parse_enumcharclass));
        $optable.newtok("term:'",    :equiv<term:>,
                        :parsed(&GGE::Perl6Regex::parse_quoted_literal));
        $optable.newtok('circumfix:[ ]', :equiv<term:>,
                        :match(GGE::Exp::Group));
        $optable.newtok('postfix:*', :looser<term:>,
                        :parsed(&GGE::Perl6Regex::parse_quant));
        $optable.newtok('postfix:+', :equiv<postfix:*>,
                        :parsed(&GGE::Perl6Regex::parse_quant));
        $optable.newtok('postfix:?', :equiv<postfix:*>,
                        :parsed(&GGE::Perl6Regex::parse_quant));
        $optable.newtok('postfix:**', :equiv<postfix:*>,
                        :parsed(&GGE::Perl6Regex::parse_quant));
        $optable.newtok('infix:',    :looser<postfix:*>, :assoc<list>,
                        :nows, :match(GGE::Exp::Concat));
        $optable.newtok('infix:|',   :looser<infix:>,
                        :nows, :match(GGE::Exp::Alt));
        $optable.newtok('prefix::',  :looser<infix:|>,
                        :parsed(&GGE::Perl6Regex::parse_modifier));
        my $match = $optable.parse($pattern);
        die 'Regex parse error'
            if $match.to < $pattern.chars;
        my $expr = $match.hash-access('expr');
        return self.bless(*, :regex(perl6exp($expr, {})));
    }

    method postcircumfix:<( )>($target, :$debug) {
        if $debug {
            say $!regex.structure;
        }
        for ^$target.chars -> $from {
            my GGE::Cursor $cursor .= new(:exp($!regex), :$target,
                                          :pos($from), :$debug);
            if $cursor.matches(:$debug) {
                return GGE::Match.new(:$target, :$from, :to($cursor.pos));
            }
        }
        return GGE::Match.new(:$target, :from(0), :to(-2));
    }

    sub parse_term($mob) {
        if $mob.target.substr($mob.to, 1) ~~ /\s/ {
            return parse_term_ws($mob);
        }
        my $m = GGE::Exp::Literal.new($mob);
        my $target = $m.target;
        $m.to += $target.substr($m.to, 1) ~~ /\w/ ?? 1 !! 0;
        $m;
    }

    sub parse_term_ws($mob) {
        my $m = GGE::Exp::WS.new($mob);
        # XXX: This is a fix for my lack of understanding of the relation
        #      between $m.from and $m.pos. There is no corresponding
        #      adjustment needed in PGE.
        if $m.to > 0 && $m.target.substr($m.to - 1, 1) eq '#' {
            --$m.to;
        }
        $m.to++ while $m.target.substr($m.to, 1) ~~ /\s/;
        if $m.target.substr($m.to, 1) eq '#' {
            my $delim = "\n";
            $m.to = defined $m.target.index($delim, $m.to)
                    ?? $m.target.index($delim, $m.to) + 1
                    !!  $m.target.chars;
        }
        $m;
    }

    sub parse_term_backslash($mob) {
        my $backchar = substr($mob.target, $mob.to, 1);
        if $backchar !~~ /\w/ {
            my $m = GGE::Exp::Literal.new($mob);
            ++$m.to;
            $m.make($backchar);
            return $m;
        }
        else {
            die 'Alphanumeric metacharacters are reserved';
        }
    }

    sub parse_enumcharclass($mob) {
        my $target = $mob.target;
        my $pos = $mob.to;
        ++$pos while $target.substr($pos, 1) ~~ /\s/;
        my Str $charlist = '';
        my Bool $isrange = False;
        while True {
            die 'No ] on that char class'
                if $pos >= $target.chars;
            given my $char = $target.substr($pos, 1) {
                when ']' {
                    last;
                }
                when '.' {
                    continue if $target.substr($pos, 2) ne '..';
                    $pos += 2;
                    ++$pos while $target.substr($pos, 1) ~~ /\s/;
                    $isrange = True;
                    next;
                }
                if $isrange {
                    $isrange = False;
                    my $fromchar = $charlist.substr(-1, 1);
                    $charlist ~= $_ for $fromchar ^.. $char;
                }
                else {
                    $charlist ~= $char;
                }
            }
            ++$pos;
            ++$pos while $target.substr($pos, 1) ~~ /\s/;
        }
        my $term = GGE::Exp::EnumCharList.new($mob);
        $term.to = $pos;
        $term.make($charlist);
        return $term;
    }

    sub parse_quoted_literal($mob) {
        my $m = GGE::Exp::Literal.new($mob);

        my $closing-quote = $m.target.index("'", $m.from + 1);
        if !defined $closing-quote {
            die "No closing ' in quoted literal";
        }
        $m.to = $closing-quote;
        $m;
    }

    sub parse_quant($mob) {
        my $m = GGE::Exp::Quant.new($mob);

        my $key = $mob.hash-access('KEY');
        my ($mod2, $mod1);
        given $m.target {
            $mod2   = .substr($m.to, 2);
            $mod1   = .substr($m.to, 1);
        }

        $m.hash-access('min') = $key eq '+' ?? 1 !! 0;
        $m.hash-access('max') = $key eq '?' ?? 1 !! Inf;;

        if $mod2 eq ':?' {
            $m.hash-access('backtrack') = EAGER;
            $m.to += 2;
        }
        elsif $mod2 eq ':!' {
            $m.hash-access('backtrack') = GREEDY;
            $m.to += 2;
        }
        elsif $mod1 eq '?' {
            $m.hash-access('backtrack') = EAGER;
            ++$m.to;
        }
        elsif $mod1 eq '!' {
            $m.hash-access('backtrack') = GREEDY;
            ++$m.to;
        }
        elsif $mod1 eq ':' {
            $m.hash-access('backtrack') = NONE;
            ++$m.to;
        }

        if $key eq '**' {
            my $brackets = False;
            if $m.target.substr($m.to, 1) eq '{' {
                $brackets = True;
                ++$m.to;
            }
            # XXX: Need to generalize this into parsing several digits
            $m.hash-access('min') = $m.hash-access('max') = $m.target.substr($m.to, 1);
            ++$m.to;
            if $m.target.substr($m.to, 2) eq '..' {
                $m.to += 2;
                $m.hash-access('max') = $m.target.substr($m.to, 1);
                ++$m.to;
            }
            if $brackets {
                die 'No "}" found'
                    unless $m.target.substr($m.to, 1) eq '}';
                ++$m.to
            }
        }

        $m;
    }

    sub parse_modifier($mob) {
        my $m = GGE::Exp::Modifier.new($mob);
        my $target = $m.target;
        my $wordchars = ($target.substr($m.to) ~~ /^\w+/).Str.chars;
        my $word = $target.substr($m.to, $wordchars);
        $m.to += $wordchars;
        $m.hash-access('key') = $word;
        $m;
    }

    multi sub perl6exp(GGE::Exp $exp is rw, %pad) {
        return $exp;
    }

    multi sub perl6exp(GGE::Exp::Modifier $exp is rw, %pad) {
        my $key = $exp.hash-access('key');
        my $temp = %pad{$key};
        %pad{$key} = 1; # XXX
        $exp[0] = perl6exp($exp[0], %pad);
        %pad{$key} = $temp;
        return $exp;
    }

    multi sub perl6exp(GGE::Exp::Concat $exp is rw, %pad) {
        my $n = $exp.elems;
        for ^$n -> $i {
            $exp[$i] = perl6exp($exp[$i], %pad);
        }
        # XXX: Two differences against PGE here: (1) no element removal,
        #      (2) no subsequent simplification in the case of only 1
        #      remaining element.
        return $exp;
    }

    multi sub perl6exp(GGE::Exp::Quant $exp is rw, %pad) {
        $exp[0] = perl6exp($exp[0], %pad);
        $exp.hash-access('backtrack') //= %pad<ratchet> ?? NONE !! GREEDY;
        return $exp;
    }
}
