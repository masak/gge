use v6;
use Test;

use GGE::OPTable;
use GGE::Match;

my GGE::OPTable $optable .= new;

# RAKUDO: I initially called the variable &ident because that's nicer, but
#         that triggered the Parrot bug wherein methods in a class collide
#         with routines outside of it. So $ident it is.
my $ident = &GGE::Match::ident;
#my $arrow = GGE::Perl6Regex.new("'->' <ident>");
for ['infix:+',           precedence => '='                                 ],
    ['infix:-',           equiv      => 'infix:+'                           ],
    ['infix:*',           tighter    => 'infix:+'                           ],
    ['infix:/',           equiv      => 'infix:*'                           ],
    ['infix:**',          tighter    => 'infix:*'                           ],
    ['infix:==',          looser     => 'infix:+'                           ],
    ['infix:=',           looser     => 'infix:==', :assoc<right>           ],
    ['infix:,',           tighter    => 'infix:=',  :assoc<list>            ],
    ['infix:;',           looser     => 'infix:=',  :assoc<list>            ],
    ['prefix:++',         tighter    => 'infix:**'                          ],
    ['prefix:--',         equiv      => 'prefix:++'                         ],
    ['postfix:++',        equiv      => 'prefix:++'                         ],
    ['postfix:--',        equiv      => 'prefix:++'                         ],
    ['prefix:-',          equiv      => 'prefix:++'                         ],
    ['term:',             tighter    => 'prefix:++', :parsed($ident)        ],
    ['circumfix:( )',     equiv      => 'term:'                             ],
    ['circumfix:[ ]',     equiv      => 'term:'                             ],
    ['postcircumfix:( )', looser     => 'term:', :nullterm,  :nows          ],
    ['postcircumfix:[ ]', equiv      => 'postcircumfix:( )', :nows          ]#,
#    ['term:->',           equiv      => 'term:', :!skipkey, :parsed($arrow) ]
-> @args { my ($name, %opts) = @args; $optable.newtok($name, |%opts) }

optable_output_is( 'a',     'term:a',                                   'Simple term' );
optable_output_is( 'a+b',   'infix:+(term:a, term:b)',                  'Simple infix' );
optable_output_is( 'a-b',   'infix:-(term:a, term:b)',                  'Simple infix' );
optable_output_is( 'a+b+c', 'infix:+(infix:+(term:a, term:b), term:c)', 'left associativity' );
optable_output_is( 'a+b-c', 'infix:-(infix:+(term:a, term:b), term:c)', 'left associativity' );
optable_output_is( 'a-b+c', 'infix:+(infix:-(term:a, term:b), term:c)', 'left associativity' );

optable_output_is( 'a+b*c', 'infix:+(term:a, infix:*(term:b, term:c))', 'tighter precedence' );
optable_output_is( 'a*b+c', 'infix:+(infix:*(term:a, term:b), term:c)', 'tighter precedence' );

optable_output_is( 'a/b/c', 'infix:/(infix:/(term:a, term:b), term:c)', 'left associativity' );
optable_output_is( 'a*b/c', 'infix:/(infix:*(term:a, term:b), term:c)', 'left associativity' );
optable_output_is( 'a/b*c', 'infix:*(infix:/(term:a, term:b), term:c)', 'left associativity' );

optable_output_is( 'a=b*c', 'infix:=(term:a, infix:*(term:b, term:c))', 'looser precedence' );

optable_output_is( 'a=b=c', 'infix:=(term:a, infix:=(term:b, term:c))', 'right associativity' );

optable_output_is(
    'a=b,c,d+e',
    'infix:=(term:a, infix:,(term:b, term:c, infix:+(term:d, term:e)))',
    'list associativity'
);

optable_output_is( 'a b',     'term:a (pos=1)', 'two terms in sequence' );
optable_output_is( 'a = = b', 'term:a (pos=1)', 'two opers in sequence' );
optable_output_is( 'a +',     'term:a (pos=1)', 'infix missing rhs' );

optable_output_is( 'a++', 'postfix:++(term:a)', 'postfix' );
optable_output_is( 'a--', 'postfix:--(term:a)', 'postfix' );
optable_output_is( '++a', 'prefix:++(term:a)',  'prefix' );
optable_output_is( '--a', 'prefix:--(term:a)',  'prefix' );

optable_output_is( '-a',  'prefix:-(term:a)',   'prefix ltm');
todo('Not ready to parse with Perl6Regex objects just yet');
optable_output_is( '->a', 'term:->a',           'prefix ltm');

optable_output_is(
    'a*(b+c)',
    'infix:*(term:a, circumfix:( )(infix:+(term:b, term:c)))',
    'circumfix parens'
);
optable_output_is(
    'a*b+c)+4',
    'infix:+(infix:*(term:a, term:b), term:c) (pos=5)',
    'extra close paren'
);
optable_output_is( '  )a*b+c)+4', 'failed', 'only close paren' );
optable_output_is( '(a*b+c',      'failed', 'missing close paren' );
optable_output_is( '(a*b+c]',     'failed', 'mismatch close paren' );

optable_output_is( 'a+++--b', 'infix:+(postfix:++(term:a), prefix:--(term:b))', 'mixed tokens' );

optable_output_is( '=a+4', 'failed', 'missing lhs term' );

optable_output_is( 'a(b,c)', 'postcircumfix:( )(term:a, infix:,(term:b, term:c))',
    'postcircumfix' );
optable_output_is( 'a (b,c)', 'term:a (pos=1)', 'nows on postcircumfix' );

optable_output_is( 'a()', 'postcircumfix:( )(term:a, null)', 'nullterm in postcircumfix' );
optable_output_is( 'a[]', 'term:a (pos=1)', 'nullterm disallowed' );

optable_output_is(
    '(a=b;c;d)',
    'circumfix:( )(infix:;(infix:=(term:a, term:b), term:c, term:d))',
    'loose list associativity in circumfix'
);

optable_output_is(
    '(a;b);d',
    'circumfix:( )(infix:;(term:a, term:b)) (pos=5)',
    'top-level stop token'
);

optable_output_is( 'a,b;c', 'infix:,(term:a, term:b) (pos=3)', 'top-level stop token' );

$optable .= new;

for ['term:',             precedence => '=', :parsed($ident)      ],
    ['postfix:*',         looser     => 'term:'                   ],
    ['infix:',            looser     => 'postfix:*', :assoc<list> ]
-> @args { my ($name, %opts) = @args; $optable.newtok($name, |%opts) }

optable_output_is( 'x a*y', 'infix:(term:x, postfix:*(term:a), term:y)',
                   'list assoc redux' );

$optable .= new;

for ['term:',             precedence => '=', :parsed($ident)      ],
    ['postfix:+',         looser     => 'term:'                   ],
    ['postfix:!',         equiv      => 'postfix:+'               ]
-> @args { my ($name, %opts) = @args; $optable.newtok($name, |%opts) }

optable_output_is( 'a+!', 'postfix:!(postfix:+(term:a))',
                   'precedence of two postfixes' );

$optable .= new;

for ['term:',             precedence => '=', :parsed($ident)         ],
    ['term:^',            equiv      => 'term:'                      ],
    ['infix:',            looser     => 'term:', :assoc<list>, :nows ]
-> @args { my ($name, %opts) = @args; $optable.newtok($name, |%opts) }

optable_output_is( '^ abc', 'infix:(term:^(), term:abc)',
                   'whitespace and infix:' );

$optable .= new;

for ['term:',             precedence => '=', :parsed($ident)           ],
    ['infix:',            looser     => 'term:', :assoc<list>, :nows   ],
    ['infix:&',           looser     => 'infix:', :assoc<list>, :nows  ],
    ['prefix:|',          looser     => 'infix:&', :assoc<list>, :nows ]
-> @args { my ($name, %opts) = @args; $optable.newtok($name, |%opts) }

optable_output_is( 'a&|b', 'infix:&(term:a, prefix:|(term:b))',
                   'infix, prefix and precedence' );

$optable .= new;

for ['term:',         precedence => '=', :parsed($ident)           ],
    ['infix:|',       looser     => 'term:',                       ],
    ['circumfix:[ ]', equiv      => 'term:', :nows                 ]
-> @args { my ($name, %opts) = @args; $optable.newtok($name, |%opts) }

optable_output_is( '[a]|b', 'infix:|(circumfix:[ ](term:a), term:b)',
                   'infix and circumfix' );

$optable .= new;

for ['term:',         precedence => '=', :parsed($ident)           ],
    ['infix:',        looser     => 'term:', :assoc<list>, :nows   ]
-> @args { my ($name, %opts) = @args; $optable.newtok($name, |%opts) }

optable_output_is( 'a b', 'term:a (pos=1)', ':tighter option',
                   :tighter<infix:> );

sub optable_output_is($test, $expected, $msg, *%opts) {
    my $output;
    if $optable.parse($test, :stop(' ;'), |%opts) -> $match {
        $output = tree($match.hash-access('expr'));
        if $match.to != $test.chars {
            $output ~= " (pos={$match.to})";
        }
    }
    else {
        $output = 'failed';
    }

    is $output, $expected, $msg;
}

sub tree($match) {
    return 'null' if !$match;
    my $r = $match.hash-access('type');
    given $match.hash-access('type') {
        when 'term:'   { $r ~= $match }
        when 'term->:' { $r ~= $match.hash-access('ident') }
        $r ~= '(' ~ (join ', ', map { tree($_) }, $match.llist) ~ ')';
    }
    return $r;
}

done-testing;
