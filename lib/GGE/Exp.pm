use v6;
use GGE::Match;

role ShowContents {
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
    BACKTRACK
>;

class GGE::Exp is GGE::Match {
    method start($, $, %state is rw) { DESCEND }
    method succeeded(%state is rw) { MATCH }
    method failed($, %state is rw) { FAIL }

    method structure($indent = 0) {
        my $contents
            = join ' ',
                (defined self.?contents ?? " ('{self.contents}')" !! ()),
                self.llist
                  ?? "[{ map { "\n{$_.structure($indent + 1)}" }, self.llist }"
                     ~ "\n{'  ' x $indent}]"
                  !! '';
        '  ' x $indent ~ self.WHAT.perl.subst(/^.*':'/, '') ~ $contents;
    }
}

class GGE::Exp::Literal is GGE::Exp does ShowContents {
    method start($string, $pos is rw, %pad) {
        if $pos < $string.chars
           && $string.substr($pos, (my $value = ~self.ast).chars) eq $value {
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

class GGE::Exp::Quant is GGE::Exp {
    method contents() {
        my ($min, $max, $bt) = map { self.hash-access($_) },
                                   <min max backtrack>;
        "{$bt.name.lc} $min..$max"
    }

    method start($_: $, $, %pad is rw) {
        %pad<reps> = 0;
        if .hash-access('min') > 0 {
            DESCEND
        }
        elsif .hash-access('max') > 0 && .hash-access('backtrack') != EAGER {
            (%pad<mempos> //= []).push(%pad<pos>);
            DESCEND
        }
        else {
            MATCH
        }
    }

    method succeeded($_: %pad is rw) {
        ++%pad<reps>;
        if .hash-access('backtrack') != EAGER
           && %pad<reps> < .hash-access('max') {
            if %pad<reps> >= .hash-access('min') {
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
        my $bt = .hash-access('backtrack');
        if $bt == EAGER
           && %pad<reps> < .hash-access('max') {
            DESCEND
        }
        elsif $bt == GREEDY && %pad<mempos> > 1 {
            $pos = pop %pad<mempos>;
            MATCH
        }
        else {
            FAIL
        }
    }
}

class GGE::Exp::CCShortcut is GGE::Exp does ShowContents {
    method matches($string, $pos is rw) {
        if $pos >= $string.chars {
            return False;
        }
        if self.ast eq '.'
           || self.ast eq '\\s' && $string.substr($pos, 1) eq ' '
           || self.ast eq '\\S' && $string.substr($pos, 1) ne ' '
           || self.ast eq '\\N' && !($string.substr($pos, 1) eq "\n"|"\r") {
            ++$pos;
            return True;
        }
        else {
            return False;
        }
    }
}

class GGE::Exp::Newline is GGE::Exp does ShowContents {
    method matches($string, $pos is rw) {
        if $pos >= $string.chars {
            return False;
        }
        if $string.substr($pos, 2) eq "\r\n" {
            $pos += 2;
            return True;
        }
        if $string.substr($pos, 1) eq "\n"|"\r" {
            ++$pos;
            return True;
        }
        else {
            return False;
        }
    }
}

class GGE::Exp::Anchor is GGE::Exp does ShowContents {
    method matches($string, $pos is rw) {
        return self.ast eq '^' && $pos == 0
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
    }
}

class GGE::Exp::Concat is GGE::Exp {
    method start($, $, %pad is rw) {
        %pad<child> = 0;
        DESCEND
    }

    method succeeded(%pad is rw) {
        if ++%pad<child> == self.elems {
            MATCH
        }
        else {
            DESCEND
        }
    }
}

class GGE::Exp::Modifier is GGE::Exp does ShowContents {
}

class GGE::Exp::EnumCharList is GGE::Exp does ShowContents {
    method matches($string, $pos is rw) {
        if $pos >= $string.chars {
            return False;
        }
        if defined(self.ast.index($string.substr($pos, 1)))
           xor self.hash-access('isnegated') {
            unless self.hash-access('iszerowidth') {
                ++$pos;
            }
            return True;
        }
        else {
            return False;
        }
    }
}

class GGE::Exp::Alt is GGE::Exp {
}

class GGE::Exp::WS is GGE::Exp {
    method matches($string, $pos is rw) {
        return True;
    }
}

class GGE::Exp::Group is GGE::Exp {
}
