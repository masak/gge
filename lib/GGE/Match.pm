use v6;

# XXX: See the file lib/GGE/Perl6Regex.pm for an explanation.
class GGE::Perl6Regex {}

# This is a workaround. See the postcircumfix:<{ }> comments below.
class Store {
    has %!hash;
    has @!array;

    method hash-access($key) { %!hash{$key} }
    method hash-exists($key) { %!hash.exists($key) }
    method hash-delete($key) { %!hash.delete($key) }
    method hash-keys()       { %!hash.keys() }

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
    has $.iscont = False;
    # XXX: This is *so* a hack. Can't think of anything better now. Sorry.
    has $.iscont2 = False;
    has $.startpos = 0;
    has $!store = Store.new;
    has $!ast;

    # RAKUDO: Shouldn't need this
    multi method new(*%_) {
        self.bless(*, |%_);
    }

    multi method new(Str $target) {
        self.new(:$target, :from(0), :to(-1), :iscont(True), :iscont2(True));
    }

    multi method new(GGE::Match $match) {
        defined $match ?? self.new(:target($match.target), :from($match.from),
                                   :to(-1),
                                   :iscont2(False), :iscont($match.iscont2),
                                   :startpos($match.to))
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
        for self.keys -> $key {
            my $elem = self.hash-access($key);
            my $name = [~] $prefix, '<', $key, '>';
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
                    say "Oops, don't know what to do with {$elem.WHAT} at $key";
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

    method keys() { $!store.hash-keys() }

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

    method name() {
        # XXX: PGE does this by code-generating a token at PGE compile time.
        #      That's a bit nicer, because it provides backtracking for free.
        #      GGE might do that too when it proves necessary.
        my $target = self.target;
        my $pos = self.to;
        my $m = self.ident();
        while $m.to > $pos && $target.substr($m.to, 2) eq '::' {
            $pos = $m.to += 2;
            $m = $m.ident();
            if $m.to == -1 {
                $m.to = $pos - 2;
            }
        }
        return $m;
    }

    method wb() {
        my $target = self.target;
        my $pos = self.to;
        my $mob = self.new(self);
        if $pos == 0 || $pos == $target.chars
           || ($target.substr($pos - 1, 1) ~~ /\w/
               xor $target.substr($pos, 1) ~~ /\w/) {
            $mob.to = $pos;
        }
        return $mob;
    }

    method cclass($regex) {
        my $target = self.target;
        my $pos = self.to;
        my $mob = self.new(self);
        if $pos < $target.chars && $target.substr($pos, 1) ~~ $regex {
            $mob.to = $pos + 1;
        }
        return $mob;
    }

    method upper()  { self.cclass: /<upper>/  }
    method lower()  { self.cclass: /<lower>/  }
    method alpha()  { self.cclass: /<alpha>/  }
    method digit()  { self.cclass: /<digit>/  }
    method xdigit() { self.cclass: /<xdigit>/ }
    method space()  { self.cclass: /<space>/  }
    method blank()  { self.cclass: /<blank>/  }
    method punct()  { self.cclass: /<punct>/  }
    method alnum()  { self.cclass: /<alnum>/  }

    method ws() {
        my $target = self.target;
        my $pos = self.to;
        my $mob = self.new(self);
        if $pos >= $target.chars {
            $mob.to = $pos;
        }
        elsif $pos == 0
              || $target.substr($pos, 1) ~~ /\W/
              || $target.substr($pos - 1, 1) ~~ /\W/ {
            while $target.substr($pos, 1) ~~ /\s/ {
                ++$pos;
            }
            $mob.to = $pos;
        }
        return $mob;
    }
}
