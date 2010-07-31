use v6;

use GGE::Match;

class GGE::Grammar is GGE::Match {
    method parse($target, :$debug, :$stepwise) {
        die "Cannot call .parse on a grammar with no TOP rule"
            unless self.can('TOP');
        my $m = self.new($target);
        $m.TOP(:$debug, :$stepwise);
    }
}
