use v6;
use GGE::Match;
use GGE::Exp;
use GGE::OPTable;
use GGE::TreeSpider;

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
        $optable.newtok('term:\\e',  :equiv<term:>,
                        :match(GGE::Exp::CCShortcut));
        $optable.newtok('term:\\E',  :equiv<term:>,
                        :match(GGE::Exp::CCShortcut));
        $optable.newtok('term:\\f',  :equiv<term:>,
                        :match(GGE::Exp::CCShortcut));
        $optable.newtok('term:\\F',  :equiv<term:>,
                        :match(GGE::Exp::CCShortcut));
        $optable.newtok('term:\\r',  :equiv<term:>,
                        :match(GGE::Exp::CCShortcut));
        $optable.newtok('term:\\R',  :equiv<term:>,
                        :match(GGE::Exp::CCShortcut));
        $optable.newtok('term:\\t',  :equiv<term:>,
                        :match(GGE::Exp::CCShortcut));
        $optable.newtok('term:\\T',  :equiv<term:>,
                        :match(GGE::Exp::CCShortcut));
        $optable.newtok('term:\\s',  :equiv<term:>,
                        :match(GGE::Exp::CCShortcut));
        $optable.newtok('term:\\S',  :equiv<term:>,
                        :match(GGE::Exp::CCShortcut));
        $optable.newtok('term:\\h',  :equiv<term:>,
                        :match(GGE::Exp::CCShortcut));
        $optable.newtok('term:\\H',  :equiv<term:>,
                        :match(GGE::Exp::CCShortcut));
        $optable.newtok('term:\\v',  :equiv<term:>,
                        :match(GGE::Exp::CCShortcut));
        $optable.newtok('term:\\V',  :equiv<term:>,
                        :match(GGE::Exp::CCShortcut));
        $optable.newtok('term:\\w',  :equiv<term:>,
                        :match(GGE::Exp::CCShortcut));
        $optable.newtok('term:\\N',  :equiv<term:>,
                        :match(GGE::Exp::CCShortcut));
        $optable.newtok('term:\\n',  :equiv<term:>,
                        :match(GGE::Exp::Newline));
        $optable.newtok('term:<[',   :equiv<term:>,
                        :parsed(&GGE::Perl6Regex::parse_enumcharclass));
        $optable.newtok('term:<-',   :equiv<term:>,
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
        $optable.newtok('infix:&',   :looser<infix:>,
                        :nows, :match(GGE::Exp::Conj));
        $optable.newtok('infix:|',   :looser<infix:&>,
                        :nows, :match(GGE::Exp::Alt));
        $optable.newtok('prefix:|',  :equiv<infix:|>,
                        :nows, :match(GGE::Exp::Alt));
        $optable.newtok('prefix::',  :looser<infix:|>,
                        :parsed(&GGE::Perl6Regex::parse_modifier));
        my $match = $optable.parse($pattern);
        die 'Perl6Regex rule error: can not parse expression'
            if $match.to < $pattern.chars;
        my $expr = $match.hash-access('expr');
        return self.bless(*, :regex(perl6exp($expr, {})));
    }

    method postcircumfix:<( )>($target, :$debug) {
        if $debug {
            say $!regex.structure;
        }
        GGE::TreeSpider.new(:$!regex, :$target, :pos(*)).crawl(:$debug);
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

    sub p6escapes($mob, :$pos! is copy) {
        my $m = GGE::Match.new($mob);
        my $target = $m.target;
        my $backchar = $target.substr($pos + 1, 1);
        $pos += 2;
        my $isbracketed = $target.substr($pos, 1) eq '[';
        $pos += $isbracketed;
        my $base = $backchar eq 'c'|'C' ?? 10
                !! $backchar eq 'o'|'O' ?? 8
                !!                         16;
        my $literal = '';
        repeat {
            ++$pos
                while $pos < $target.chars && $target.substr($pos, 1) ~~ /\s/;
            my $decnum = 0;
            while $pos < $target.chars
                  && defined(my $digit = '0123456789abcdef0123456789ABCDEF'\
                          .index($target.substr($pos, 1))) {
                $digit %= 16;
                $decnum *= $base;
                $decnum += $digit;
                ++$pos;
            }
            my $char = chr($decnum);
            $literal ~= $char;
            ++$pos
                while $pos < $target.chars && $target.substr($pos, 1) ~~ /\s/;
        } while $target.substr($pos, 1) eq ',' && ++$pos;
        die "Missing close bracket for \\x[...], \\o[...], or \\c[...]"
            if $isbracketed && $target.substr($pos, 1) ne ']';
        $pos += $isbracketed;
        $m.make($literal);
        $m.to = $pos - 1;
        $m;
    }

    sub parse_term_backslash($mob) {
        my $backchar = substr($mob.target, $mob.to, 1);
        # XXX: Should really be treating \s, \v, \h, \e, \f, \r, \t et al
        #      in the same way as \x below. The charclass information is
        #      specific to Perl 6 regexes, and belongs here in Perl6Regex,
        #      not in GGE::Exp. It would also follow PGE better.
        if $backchar eq 'x'|'X'|'c'|'C'|'o'|'O' {
            my $isnegated = $backchar eq $backchar.uc;
            my $escapes = p6escapes($mob, :pos($mob.to - 1));
            die 'Unable to parse \x, \c, or \o value'
                unless $escapes;
            # XXX: Can optimize here by special-casing on 1-elem charlist.
            #      PGE does this.
            my GGE::Exp $m = $isnegated ?? GGE::Exp::EnumCharList.new($mob)
                                        !! GGE::Exp::Literal.new($mob);
            $m.hash-access('isnegated') = $isnegated;
            $m.make($escapes.ast);
            $m.to = $escapes.to;
            return $m;
        }
        die 'Alphanumeric metacharacters are reserved'
            if $backchar ~~ /\w/;

        my $m = GGE::Exp::Literal.new($mob);
        ++$m.to;
        $m.make($backchar);
        return $m;
    }

    sub parse_enumcharclass($mob) {
        my $target = $mob.target;
        my $pos = $mob.to;
        my $key = $mob.hash-access('KEY');
        # This is only correct as long as we don't do subrules.
        if $key ne '<[' {
            ++$pos;
        }
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
        $term.make($charlist);
        if $key eq '<-' {
            $term.hash-access('isnegated') = True;
            $term.hash-access('iszerowidth') = True;
            my $subtraction = GGE::Exp::Concat.new($mob);
            my $everything = GGE::Exp::CCShortcut.new($mob);
            $everything.make('.');
            $subtraction[0] = $term;
            $subtraction[1] = $everything;
            $term = $subtraction;
        }
        $term.to = $pos;
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

    multi sub perl6exp(GGE::Exp::Alt $exp is rw, %pad) {
        if !defined $exp[1] {
            return perl6exp($exp[0], %pad);
        }
        if $exp[1] ~~ GGE::Exp::WS {
            die 'Perl6Regex rule error: nothing not allowed in alternations';
        }
        $exp[0] = perl6exp($exp[0], %pad);
        $exp[1] = perl6exp($exp[1], %pad);
        return $exp;
    }

    multi sub perl6exp(GGE::Exp::Conj $exp is rw, %pad) {
        if $exp[1] ~~ GGE::Exp::Alt && !defined $exp[1][1] {
            die 'Perl6Regex rule error: "&|" not allowed';
        }
        $exp[0] = perl6exp($exp[0], %pad);
        $exp[1] = perl6exp($exp[1], %pad);
        return $exp;
    }
}
