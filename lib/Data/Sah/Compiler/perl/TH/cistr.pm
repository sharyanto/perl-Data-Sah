package Data::Sah::Compiler::perl::TH::cistr;

use 5.010;
use Log::Any '$log';
use Moo;
extends 'Data::Sah::Compiler::perl::TH::str';
with 'Data::Sah::Type::cistr';

# VERSION

# XXX cache lc() result so it's not done on every clause

sub superclause_comparable {
    my ($self, $which, $cd) = @_;
    my $c  = $self->compiler;
    my $ct = $cd->{cl_term};
    my $dt = $cd->{data_term};

    if ($which eq 'is') {
        $c->add_ccl($cd, "lc($dt) eq lc($ct)");
    } elsif ($which eq 'in') {
        $c->add_smartmatch_pragma($cd);
        $c->add_ccl($cd, "lc($dt) ~~ [map {lc} \@{ $ct }]");
    }
}

sub superclause_sortable {
    my ($self, $which, $cd) = @_;
    my $c  = $self->compiler;
    my $cv = $cd->{cl_value};
    my $ct = $cd->{cl_term};
    my $dt = $cd->{data_term};

    if ($which eq 'min') {
        $c->add_ccl($cd, "lc($dt) ge lc($ct)");
    } elsif ($which eq 'xmin') {
        $c->add_ccl($cd, "lc($dt) gt lc($ct)");
    } elsif ($which eq 'max') {
        $c->add_ccl($cd, "lc($dt) le lc($ct)");
    } elsif ($which eq 'xmax') {
        $c->add_ccl($cd, "lc($dt) lt lc($ct)");
    } elsif ($which eq 'between') {
        if ($cd->{cl_is_expr}) {
            $c->add_ccl($cd, "lc($dt) ge lc($ct\->[0]) && ".
                            "lc($dt) le lc($ct\->[1])");
        } else {
            # simplify code
            $c->add_ccl($cd, "lc($dt) ge ".$c->literal(lc $cv->[0]).
                            " && lc($dt) le ".$c->literal(lc $cv->[1]));
        }
    } elsif ($which eq 'xbetween') {
        if ($cd->{cl_is_expr}) {
            $c->add_ccl($cd, "lc($dt) gt lc($ct\->[0]) && ".
                            "lc($dt) lt lc($ct\->[1])");
        } else {
            # simplify code
            $c->add_ccl($cd, "lc($dt) gt ".$c->literal(lc $cv->[0]).
                            " && lc($dt) lt ".$c->literal(lc $cv->[1]));
        }
    }
}

sub superclause_has_elems {
    my ($self_th, $which, $cd) = @_;
    my $c  = $self_th->compiler;
    my $cv = $cd->{cl_value};
    my $ct = $cd->{cl_term};
    my $dt = $cd->{data_term};

    if ($which eq 'has') {
        $c->add_ccl($cd, "index(lc($dt), lc($ct)) > -1");
    } else {
        $self_th->SUPER::superclause_has_elems($which, $cd);
    }
}

# turn "(?-xism:blah)" to "(?i-xsm:blah)"
sub __change_re_str_switch {
    my $re = shift;

    if ($^V ge v5.14.0) {
        state $sub = sub { my $s = shift; $s =~ /i/ ? $s : "i$s" };
        $re =~ s/\A\(?\^(\w*):/"(?".$sub->($1).":"/e;
    } else {
        state $subl = sub { my $s = shift; $s =~ /i/ ? $s : "i$s" };
        state $subr = sub { my $s = shift; $s =~ s/i//; $s };
        $re =~ s/\A\(\?(\w*)-(\w*):/"(?".$subl->($1)."-".$subr->($2).":"/e;
    }
    return $re;
}

sub clause_match {
    my ($self, $cd) = @_;
    my $c  = $self->compiler;
    my $cv = $cd->{cl_value};
    my $ct = $cd->{cl_term};
    my $dt = $cd->{data_term};

    if ($cd->{cl_is_expr}) {
        $c->add_ccl($cd, join(
            "",
            "ref($ct) eq 'Regexp' ? $dt =~ qr/$ct/i : ",
            "do { my \$re = $ct; eval { \$re = /\$re/i; 1 } && ",
            "$dt =~ \$re }",
        ));
    } else {
        # simplify code and we can check regex at compile time
        my $re = $c->_str2reliteral($cd, $cv);
        $re = __change_re_str_switch($re);
        $c->add_ccl($cd, "$dt =~ /$re/i");
    }
}

1;
# ABSTRACT: perl's type handler for type "cistr"

=for Pod::Coverage ^(clause_.+|superclause_.+)$

=head1 NOTES

Should probably be reimplemented using special Perl string type, or special Perl
operators, instead of simulated using C<lc()> on a per-clause basis. The
implementation as it is now is not "contagious", e.g. C<< [cistr =>
check_each_elem => '$_ eq "A"'] >> should be true even if data is C<"Aaa">,
since one would expect C<<$_ eq "A">> is also done case-insensitively, but it is
currently internally implemented by converting data to lowercase and splitting
per character to become C<<["a", "a", "a"]>>.

Or, avoid C<cistr> altogether and use C<prefilters> to convert to
lowercase/uppercase first before processing.

=cut
