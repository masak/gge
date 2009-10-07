use v6;

# RAKUDO: See the postcircumfix:<{ }> below.
class Store {
    has %.attrs;

    method access($key) { %!attrs{$key} }
}

class GGE::Match {
    has $.target;
    has $.from = 0;
    has $.to is rw = 0;
    has $!store = Store.new;

    # RAKUDO: Shouldn't need this
    multi method new(*%_) {
        self.bless(*, |%_);
    }

    multi method new(GGE::Match $match) {
        defined $match ?? $match.clone() !! self.new();
    }

    method true() {
        return $!to >= $!from;
    }

    method dump_str() {
        ?self.true()
            ?? sprintf '<%s @ 0>', $!target.substr($!from, $!to - $!from)
            !! '';
    }

    method Str() {
        $!target.substr($!from, $!to - $!from)
    }

    # RAKUDO: There's a bug preventing me from using hash lookup in a
    #         postcircumfix:<{ }> method. This workaround uses the above
    #         class to put the problematic hash lookup out of reach.
    method postcircumfix:<{ }>($key) { $!store.access($key) }

    method ident() {
        my $mob = self.new(self);
        my $target = $mob.target;
        my $pos = $mob.to;
        if $target.substr($pos, 1) ~~ /<alpha>/ {
            ++$pos while $pos < $target.chars
                         && $target.substr($pos, 1) ~~ /\w/;
            $mob.to = $pos;
        }
        # RAKUDO: Putting 'return' here makes Rakudo blow up.
        $mob;
    }
}
