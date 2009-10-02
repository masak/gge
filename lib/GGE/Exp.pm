use v6;

class GGE::Exp {}

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
}

class GGE::Exp::Anchor is GGE::Exp {
    has $.type;
}
