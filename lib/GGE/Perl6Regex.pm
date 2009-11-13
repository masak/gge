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
        $optable.newtok('term:\\',   :equiv<term:>,
                        :parsed(&GGE::Perl6Regex::parse_term_backslash));
        $optable.newtok('term:^',    :equiv<term:>,
                        :match(GGE::Exp::Anchor));
        $optable.newtok('term:$',    :equiv<term:>, # XXX not per PGE
                        :match(GGE::Exp::Anchor));
        $optable.newtok('term:<<',   :equiv<term:>,
                        :match(GGE::Exp::Anchor));
        $optable.newtok('term:>>',   :equiv<term:>,
                        :match(GGE::Exp::Anchor));
        $optable.newtok('term:.',    :equiv<term:>,
                        :match(GGE::Exp::CCShortcut));
        $optable.newtok('term:\\n',  :equiv<term:>,
                        :match(GGE::Exp::CCShortcut));
        $optable.newtok('term:\\N',  :equiv<term:>,
                        :match(GGE::Exp::CCShortcut));
        $optable.newtok('term:\\s',  :equiv<term:>,
                        :match(GGE::Exp::CCShortcut));
        $optable.newtok('term:\\S',  :equiv<term:>,
                        :match(GGE::Exp::CCShortcut));
        $optable.newtok('term:\\w',  :equiv<term:>,
                        :match(GGE::Exp::CCShortcut));
        $optable.newtok("term:'",    :equiv<term:>,
                        :parsed(&GGE::Perl6Regex::parse_quoted_literal));
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
        $optable.newtok('prefix::',  :looser<infix:>,
                        :parsed(&GGE::Perl6Regex::parse_modifier));
        my $expr = $optable.parse($pattern)<expr>;
        die 'Regex parse error'
            unless $expr;
        return self.bless(*, :regex(perl6exp($expr, {})));
    }

    method postcircumfix:<( )>($target, :$debug) {
        if $debug {
            say $!regex.structure;
        }
        for ^$target.chars -> $from {
            my GGE::Cursor $cursor .= new(:top($!regex), :$target,
                                          :pos($from), :$debug);
            if $cursor.matches(:$debug) {
                return GGE::Match.new(:$target, :$from, :to($cursor.pos));
            }
        }
        return GGE::Match.new(:$target, :from(0), :to(-2));
    }

    sub parse_term($mob) {
        my $m = GGE::Exp::Literal.new($mob);
        $m.from = $mob.to;
        my $target = $m.target;
        $m.from++ while $m.target.substr($m.from, 1) ~~ /\s/;
        $m.to = $m.from + ($target.substr($m.from, 1) ~~ /\w/ ?? 1 !! 0);
        $m;
    }

    sub parse_term_backslash($mob) {
        my $m = GGE::Exp::Literal.new($mob);
        $m.from = $mob.to;
        $m.to = $m.from + 2;
        $m;
    }

    sub parse_quoted_literal($mob) {
        my $m = GGE::Exp::Literal.new($mob);
        $m.from = $mob.to;

        my $closing-quote = $m.target.index("'", $m.from + 1);
        if !defined $closing-quote {
            die "No closing ' in quoted literal";
        }
        $m.to = $closing-quote;
        $m;
    }

    sub parse_quant($mob) {
        my $m = GGE::Exp::Quant.new($mob);
        $m.from = $mob.to;

        my $key = $mob<KEY>;
        $m.to = $m.from + $key.chars;
        my ($mod2, $mod1);
        given $m.target {
            $mod2   = .substr($m.to, 2);
            $mod1   = .substr($m.to, 1);
        }

        $m<min> = $key eq '+' ?? 1 !! 0;
        $m<max> = $key eq '?' ?? 1 !! Inf;;

        if $mod2 eq ':?' {
            $m<backtrack> = EAGER;
            $m.to += 2;
        }
        elsif $mod2 eq ':!' {
            $m<backtrack> = GREEDY;
            $m.to += 2;
        }
        elsif $mod1 eq '?' {
            $m<backtrack> = EAGER;
            ++$m.to;
        }
        elsif $mod1 eq '!' {
            $m<backtrack> = GREEDY;
            ++$m.to;
        }
        elsif $mod1 eq ':' {
            $m<backtrack> = NONE;
            ++$m.to;
        }

        if $key eq '**' {
            my $brackets = False;
            if $m.target.substr($m.to, 1) eq '{' {
                $brackets = True;
                ++$m.to;
            }
            # XXX: Need to generalize this into parsing several digits
            $m<min> = $m<max> = $m.target.substr($m.to, 1);
            ++$m.to;
            if $m.target.substr($m.to, 2) eq '..' {
                $m.to += 2;
                $m<max> = $m.target.substr($m.to, 1);
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
        $m.from = $mob.to;
        my $target = $m.target;
        ++$m.to;
        my $wordchars = ($target.substr($m.to) ~~ /^\w+/).Str.chars;
        my $word = $target.substr($m.to, $wordchars);
        $m.to += $wordchars;
        $m<key> = $word;
        $m;
    }

    multi sub perl6exp(GGE::Exp $exp is rw, %pad) {
        return $exp;
    }

    multi sub perl6exp(GGE::Exp::Modifier $exp is rw, %pad) {
        my $key = $exp<key>;
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
        $exp<backtrack> //= %pad<ratchet> ?? NONE !! GREEDY;
        return $exp;
    }
}
