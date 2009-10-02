use v6;

class GGE::Exp {}

class GGE::Exp::Literal is GGE::Exp {
    has $.value;

    method matches($string, $pos is rw) {
        if $pos >= $string.chars {
            return False;
        }
        if $!value eq '.' {
            ++$pos;
            return True;
        }
        else {
            if $string.substr($pos, $!value.chars) eq $!value {
                $pos += $!value.chars;
                return True;
            }
        }
    }

    method Str { qq['$.value'] }
}

class GGE::Exp::Quant is GGE::Exp {
    has $.type    is rw;
    has $.ratchet is rw;
    has $.min     is rw;
    has $.max     is rw;
    has $.expr    is rw;

    method Str { 'quantifier expression' }
}

class GGE::Exp::CCShortcut is GGE::Exp {
    has $.type;

    method matches($string, $pos is rw) {
        if $!type eq 's' && $string.substr($pos, 1) eq ' ' {
            ++$pos;
            return True;
        }
        elsif $!type eq 'S' && $pos < $string.chars
              && $string.substr($pos, 1) ne ' ' {
            ++$pos;
            return True;
        }
    }
}

class GGE::Exp::Anchor is GGE::Exp {
    has $.type;

    method matches($string, $pos is rw) {
        return $!type eq '^' && $pos == 0
            || $!type eq '$' && $pos == $string.chars;
    }
}
