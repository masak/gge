use v6;

class GGE::Exp {}

class GGE::Exp::Quant is GGE::Exp {
    has $.type    is rw;
    has $.ratchet is rw;
    has $.min     is rw;
    has $.max     is rw;
    has $.expr    is rw;
    has $.reps    is rw;
}

class GGE::Exp::CCShortcut is GGE::Exp {
    has $.type;
}
