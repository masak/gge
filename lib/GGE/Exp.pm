use v6;
use GGE::Match;

enum GGE_BACKTRACK <
    GREEDY
    EAGER
    NONE
>;

class GGE::Exp is GGE::Match {}

class GGE::Exp::Literal is GGE::Exp {
    method matches($string, $pos is rw) {
        if $pos >= $string.chars {
            return False;
        }
        my $value = self.Str;
        if $string.substr($pos, $value.chars) eq $value {
            $pos += $value.chars;
            return True;
        }
    }
}

class GGE::Exp::Quant is GGE::Exp {
    has &.backtrack = { False };

    method matches($string, $pos is rw) {
        for ^self<min> {
            return False if !self[0].matches($string, $pos);
        }
        my $n = self<min>;
        if self<backtrack> == EAGER {
            &!backtrack = {
                $n++ < self<max> && self[0].matches($string, $pos)
            };
        }
        else {
            my @positions;
            while $n++ < self<max> {
                push @positions, $pos;
                last if !self[0].matches($string, $pos);
            }
            if self<backtrack> == GREEDY {
                &!backtrack = {
                    @positions && $pos = pop @positions
                };
            }
        }
        return True;
    }
}

class GGE::Exp::CCShortcut is GGE::Exp {
    method matches($string, $pos is rw) {
        if $pos >= $string.chars {
            return False;
        }
        if self.Str eq '.'
           || self.Str eq '\\s' && $string.substr($pos, 1) eq ' '
           || self.Str eq '\\S' && $string.substr($pos, 1) ne ' ' {
            ++$pos;
            return True;
        }
        else {
            return False;
        }
    }
}

class GGE::Exp::Anchor is GGE::Exp {
    method matches($string, $pos is rw) {
        return self.Str eq '^' && $pos == 0
            || self.Str eq '$' && $pos == $string.chars;
    }
}

class GGE::Exp::Concat is GGE::Exp {
}

class GGE::Exp::Modifier is GGE::Exp {
}
