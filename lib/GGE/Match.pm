use v6;

class GGE::Perl6Regex { ... }

class GGE::Match is Cool {
    has $.target;
    has $.from is rw = 0;
    has $.to is rw = 0;
    has $.iscont = False;
    has $.startpos = 0;
    has $!ast;

    has %!properties is rw;
    has @!children is rw;

    multi method new(*%_) {
        self.bless(*, |%_);
    }

    multi method new(Str $target) {
        self.new(:$target, :from(0), :to(-1), :iscont(True));
    }

    multi method new(GGE::Match $match) {
        defined $match ?? self.new(:target($match.target), :from($match.from),
                                   :to(-1), :iscont(False),
                                   :startpos($match.to))
                       !! self.new();
    }

    method Bool() {
        return $!to >= $!from;
    }

    method dump_str($prefix = '', $b1 = '[', $b2 = ']') {
        my $out = sprintf "%s: <%s @ %d> \n",
                          $prefix,
                                $!target.substr($!from, $!to - $!from),
                                     $!from;
        if self.list {
            for self.list.kv -> $index, $elem {
                my $name = [~] $prefix, $b1, $index, $b2;
                given $elem {
                    when !.defined { next }
                    when GGE::Match {
                        $out ~= $elem.dump_str($name, $b1, $b2);
                    }
                    when Array {
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
            my $elem = self{$key};
            my $name = [~] $prefix, '<', $key, '>';
            given $elem {
                when !.defined { next }
                when GGE::Match {
                    $out ~= $elem.dump_str($name, $b1, $b2);
                }
                when Array {
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
        # RAKUDO: Stringification needed due to [perl #73462]
        (~$!target).substr($!from, $!to - $!from)
    }

    method postcircumfix:<{ }>($key) { %!properties{$key} }

    # RAKUDO: All these can be shortened down to a 'handles' declaration,
    #         once Rakudo implements 'handles' again.
    method exists($key) { %!properties.exists($key) }
    method delete($key) { %!properties.delete($key) }
    method keys() { %!properties.keys() }

    method postcircumfix:<[ ]>($index) { @!children[$index] }

    method push($submatch) { @!children.push($submatch) }
    method pop() { @!children.pop() }
    method list() { @!children.list() }
    method elems() { @!children.elems() }
    method clear() { @!children = () }

    method make($obj) {
        $!ast = $obj;
    }

    method ast() {
        $!ast // self.Str
    }

    our method ident() {
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
    method cntrl()  { self.cclass: /<cntrl>/  }
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
