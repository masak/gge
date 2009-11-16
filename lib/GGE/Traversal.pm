use v6;

use GGE::Exp;

class GGE::Traversal;

has %.next;
has $!current;

submethod step($exp) {
    my $curstr = $!current ~~ GGE::Exp ?? $!current.WHICH !! $!current;
    %!next{$curstr} = $exp;
    $!current = $exp;
}

submethod BUILD(GGE::Exp :$exp!) {
    $!current = 'START';
    self.weave($exp);
    self.step('END');
}

multi method weave(GGE::Exp $exp) {
    self.step($exp);
}

multi method weave(GGE::Exp::Modifier $exp) {
    self.weave($exp.llist[0]);
}

multi method weave(GGE::Exp::Group $exp) {
    self.weave($exp.llist[0]);
}

multi method weave(GGE::Exp::Concat $exp) {
    for $exp.llist -> $child {
        self.weave($child);
    }
}
