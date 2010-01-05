use v6;
use GGE::Match;

role GGE::ShowContents {
    method contents() {
        self.ast;
    }
}

# RAKUDO: Could name this one GGE::Exp::Actions or something, if enums
#         with '::' in them worked, which they don't. [perl #71460]
enum Action <
    DESCEND
    MATCH
    FAIL
    FAIL_GROUP
    FAIL_RULE
    BACKTRACK
>;

role GGE::Backtracking {}  # a GGE::Exp involved in backtracking
role GGE::Container {}     # a GGE::Exp containing other GGE::Exp nodes
role GGE::MultiChild does GGE::Container {}  # ...containing several...

# RAKUDO: Blablabla, GGE::Exp::Cut, blablabla, see above. [perl #71460]
enum Cut <
    CUT_GROUP
    CUT_RULE
    CUT_MATCH
>;

class GGE::Exp is GGE::Match {
    method start($, $, %) { MATCH }
    method succeeded($, %) { MATCH }
    method failed($, %) { FAIL }
    method failed-group($, %) { FAIL_GROUP }
    method failed-rule($, %) { FAIL_RULE }

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
}

class GGE::Exp::Literal is GGE::Exp does GGE::ShowContents {
    method start($string, $pos is rw, %pad) {
        my $value = ~self.ast;
        if $pos < $string.chars
           && (self.hash-access('ignorecase')
                 && $string.substr($pos, $value.chars).lc eq $value.lc
               || $string.substr($pos, $value.chars) eq $value) {
            $pos += $value.chars;
            MATCH
        }
        else {
            FAIL
        }
    }
}

enum GGE_BACKTRACK <
    GREEDY
    EAGER
    NONE
>;

class GGE::Exp::Quant is GGE::Exp does GGE::Backtracking does GGE::Container {
    method contents() {
        my ($min, $max, $bt) = map { self.hash-access($_) },
                                   <min max backtrack>;
        $bt //= GREEDY;
        "{$bt.name.lc} $min..$max"
    }

    method start($_: $, $, %pad is rw) {
        %pad<reps> = 0;
        my $bt = .hash-access('backtrack') // GREEDY;
        if .hash-access('min') > 0 {
            DESCEND
        }
        elsif .hash-access('max') > 0 && $bt != EAGER {
            if %pad<reps> >= .hash-access('min') {
                (%pad<mempos> //= []).push(%pad<pos>);
            }
            DESCEND
        }
        else {
            MATCH
        }
    }

    method succeeded($_: $, %pad is rw) {
        ++%pad<reps>;
        if (.hash-access('backtrack') // GREEDY) != EAGER
           && %pad<reps> < .hash-access('max') {
            if %pad<reps> > .hash-access('min') {
                (%pad<mempos> //= []).push(%pad<pos>);
            }
            DESCEND
        }
        else {
            MATCH
        }
    }

    method failed($_: $pos, %pad is rw) {
        if %pad<reps> >= .hash-access('min') {
            MATCH
        }
        else {
            FAIL
        }
    }

    method backtracked($_: $pos is rw, %pad) {
        my $bt = .hash-access('backtrack') // GREEDY;
        if $bt == EAGER
           && %pad<reps> < .hash-access('max') {
            DESCEND
        }
        elsif $bt == GREEDY && +%pad<mempos> {
            $pos = pop %pad<mempos>;
            MATCH
        }
        else {
            FAIL
        }
    }
}

class GGE::Exp::CCShortcut is GGE::Exp does GGE::ShowContents {
    method start($string, $pos is rw, %pad) {
        my $cc-char = self.ast.substr(1);
        if $pos >= $string.chars {
            FAIL
        }
        elsif self.ast eq '.'
           || self.ast eq '\\N' && !($string.substr($pos, 1) eq "\n"|"\r")
           || self.ast eq '\\s' && $string.substr($pos, 1) ~~ /\s/
           || self.ast eq '\\S' && $string.substr($pos, 1) ~~ /\S/
           || self.ast eq '\\w' && $string.substr($pos, 1) ~~ /\w/
           || self.ast eq '\\W' && $string.substr($pos, 1) ~~ /\W/
           || self.ast eq '\\d' && $string.substr($pos, 1) ~~ /\d/
           || self.ast eq '\\D' && $string.substr($pos, 1) ~~ /\D/ {
            ++$pos;
            MATCH
        }
        else {
            FAIL
        }
    }
}

class GGE::Exp::Newline is GGE::Exp does GGE::ShowContents {
    method start($string, $pos is rw, %pad) {
        if $pos >= $string.chars {
            FAIL
        }
        elsif $string.substr($pos, 2) eq "\r\n" {
            $pos += 2;
            MATCH
        }
        elsif $string.substr($pos, 1) eq "\n"|"\r" {
            ++$pos;
            MATCH
        }
        else {
            FAIL
        }
    }
}

class GGE::Exp::Anchor is GGE::Exp does GGE::ShowContents {
    method start($string, $pos is rw, %pad) {
        my $matches = self.ast eq '^' && $pos == 0
            || self.ast eq '$' && $pos == $string.chars
            || self.ast eq '<<' && $string.substr($pos, 1) ~~ /\w/
               && ($pos == 0 || $string.substr($pos - 1, 1) !~~ /\w/)
            || self.ast eq '>>' && $pos > 0
               && $string.substr($pos - 1, 1) ~~ /\w/
               && ($pos == $string.chars || $string.substr($pos, 1) !~~ /\w/)
            || self.ast eq '^^' && ($pos == 0 || $pos < $string.chars
               && $string.substr($pos - 1, 1) eq "\n")
            || self.ast eq '$$' && ($string.substr($pos, 1) eq "\n"
               || $pos == $string.chars
                  && ($pos < 1 || $string.substr($pos - 1, 1) ne "\n"));
        $matches ?? MATCH !! FAIL;
    }
}

class GGE::Exp::Concat is GGE::Exp does GGE::MultiChild {
    method start($, $, %pad is rw) {
        %pad<child> = 0;
        DESCEND
    }

    method succeeded($, %pad is rw) {
        if ++%pad<child> == self.elems {
            MATCH
        }
        else {
            DESCEND
        }
    }
}

class GGE::Exp::Modifier   is GGE::Exp
                         does GGE::ShowContents
                         does GGE::Container
{
    method contents() {
        self.hash-access('key');
    }

    method start($, $, %) { DESCEND }
}

class GGE::Exp::EnumCharList is GGE::Exp does GGE::ShowContents {
    method contents() {
        my $zw   = self.hash-access('iszerowidth') ?? 'zw '  !! '';
        my $neg  = self.hash-access('isnegated')   ?? 'neg ' !! '';
        my $list = self.ast;
        qq[$zw$neg$list]
    }

    method start($string, $pos is rw, %pad) {
        if $pos >= $string.chars && !self.hash-access('iszerowidth') {
            FAIL
        }
        elsif defined(self.ast.index($string.substr($pos, 1)))
           xor self.hash-access('isnegated') {
            unless self.hash-access('iszerowidth') {
                ++$pos;
            }
            MATCH
        }
        else {
            FAIL
        }
    }
}

class GGE::Exp::Alt is GGE::Exp does GGE::MultiChild does GGE::Backtracking {
    method start($, $pos, %pad) {
        %pad<child> = 0;
        %pad<orig-pos> = $pos;
        DESCEND
    }

    method failed($pos is rw, %pad is rw) {
        self.backtracked($pos, %pad);
    }

    method backtracked($pos is rw, %pad is rw) {
        if %pad<child> {
            FAIL
        }
        else {
            $pos = %pad<orig-pos>;
            %pad<child> = 1;
            DESCEND
        }
    }
}

class GGE::Exp::Conj is GGE::Exp does GGE::MultiChild {
    method start($, $pos, %pad) {
        %pad<child> = 0;
        %pad<orig-pos> = $pos;
        DESCEND
    }

    method succeeded($pos is rw, %pad) {
        if %pad<child> {
            if $pos == %pad<firstmatch-pos> {
                MATCH
            }
            else {
                FAIL
            }
        }
        else {
            %pad<firstmatch-pos> = $pos;
            $pos = %pad<orig-pos>;
            %pad<child> = 1;
            DESCEND
        }
    }
}

class GGE::Exp::Group is GGE::Exp does GGE::Container {
    method start($, $, %) { DESCEND }
    method failed-group($, %) { FAIL }
}

class GGE::Exp::CGroup is GGE::Exp does GGE::Container {
    method start($, $, %) { DESCEND }
    method failed-group($, %) { FAIL }
}

class GGE::Exp::Cut is GGE::Exp does GGE::Backtracking {
    method backtracked($pos, %pad) {
        if self.hash-access('cutmark') == CUT_GROUP {
            FAIL_GROUP
        }
        else {
            FAIL_RULE
        }
    }
}
