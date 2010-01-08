use v6;

# This is a workaround. See the postcircumfix:<{ }> comments below.
class Store {
    has %!hash is rw;
    has @!array is rw;

    method hash-access($key) { %!hash{$key} }
    method hash-exists($key) { %!hash.exists($key) }
    method hash-delete($key) { %!hash.delete($key) }

    method array-access($index) { @!array[$index] }
    method array-setelem($index, $value) { @!array[$index] = $value }
    method array-push($item) { @!array.push($item) }
    method array-pop() { @!array.pop() }
    method array-list() { @!array.list }
    method array-elems() { @!array.elems }
    method array-clear() { @!array = () }
}

class GGE::Match {
    has $.target;
    has $.from is rw = 0;
    has $.to is rw = 0;
    has $!store = Store.new;
    has $!ast;

    # RAKUDO: Shouldn't need this
    multi method new(*%_) {
        self.bless(*, |%_);
    }

    multi method new(GGE::Match $match, :$pos) {
        defined $match ?? self.new(:target($match.target), :from($match.from),
                                   :to(-1))
                       !! self.new();
    }

    method true() {
        return $!to >= $!from;
    }

    method dump_str($prefix = '', $b1 = '[', $b2 = ']') {
        my $out = sprintf "%s: <%s @ %d> \n",
                          $prefix,
                                $!target.substr($!from, $!to - $!from),
                                     $!from;
        if self.llist {
            for self.llist.kv -> $index, $elem {
                my $name = [~] $prefix, $b1, $index, $b2;
                given $elem {
                    when !.defined { next }
                    when GGE::Match {
                        $out ~= $elem.dump_str($name, $b1, $b2);
                    }
                    when List {
                        for $elem.list.kv -> $i2, $e2 {
                            my $n2 = [~] $name, $b1, $i2, $b2;
                            $out ~= $e2.dump_str($n2, $b1, $b2);
                        }
                    }
                    when * {
                        say "Oops, don't know what to do with {$elem.WHAT}";
                    }
                }
            }
        }
        return $out;
    }

    method Str() {
        $!target.substr($!from, $!to - $!from)
    }

    # RAKUDO: There's a bug preventing me from using hash lookup in a
    #         postcircumfix:<{ }> method. This workaround uses the above
    #         class to put the problematic hash lookup out of reach.
    # RAKUDO: Now there's also a bug which spews out false warnings due to
    #         postcircumfix:<{ }> declarations. Will have to do without
    #         this declaration until that is resolved, in order to be able
    #         to build GGE. [perl #70922]
  #  method postcircumfix:<{ }>($key) { $!store.hash-access($key) }
    method hash-access($key) { $!store.hash-access($key) }
    method postcircumfix:<[ ]>($index) { $!store.array-access($index) }

    method set($index, $value) { $!store.array-setelem($index, $value) }

    method exists($key) { $!store.hash-exists($key) }

    method delete($key) { $!store.hash-delete($key) }

    method push($submatch) {
        $!store.array-push($submatch);
    }

    method pop() {
        $!store.array-pop();
    }

    method llist() {
        $!store.array-list();
    }

    method elems() {
        $!store.array-elems();
    }

    method clear() {
        $!store.array-clear();
    }

    method make($obj) {
        $!ast = $obj;
    }

    method ast() {
        $!ast // self.Str
    }

    method ident() {
        my $mob = self.new(self);
        my $target = $mob.target;
        my $pos = self.to;
        if $target.substr($pos, 1) ~~ /<alpha>/ {
            ++$pos while $pos < $target.chars
                         && $target.substr($pos, 1) ~~ /\w/;
            $mob.to = $pos;
        }
        # RAKUDO: Putting 'return' here makes Rakudo blow up.
        $mob;
    }
}
