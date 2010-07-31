use v6;

use GGE::Perl6Regex;

class GGE::Grammar is GGE::Match {
    method regex($name, $rule) {
        GGE::Perl6Regex.new($rule, :grammar(self.WHAT.perl), :$name);
    }

    method parse($target, :$debug, :$stepwise) {
        die "Cannot call .parse on a grammar with no TOP rule"
            unless self.can('TOP');
        my $m = self.new($target);
        $m.TOP(:$debug, :$stepwise);
    }
}
