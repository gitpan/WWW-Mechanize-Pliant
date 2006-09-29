package WWW::Mechanize::Pliant;
use base qw(WWW::Mechanize);
use HTML::Entities qw(decode_entities);

our $VERSION = 0.1;

=head1 ABSTRACT

WWW::Mechanize::Pliant - crawl Pliant-based websites

=head1 SYNOPSIS

Pliant:


  var Str search 
  input "Find:" search 
  button "Go"
    #...

Or, 

  var Str search 
  input "Find:" search 
  icon "images/go.png" help "Go"
    #...

Mechanize code, for both cases:

  $mech = WWW::Mechanize::Pliant->new(cookie_jar => {});
  $mech->get("http://mypliantsite.com");
  $mech->form->set_field("search", "Beads Game");
  $mech->form->click("Go");

=head1 DETAILS

=cut

sub decoded_content {
  my ($self) = @_;
  return decode_entities($self->content);
}

sub postprocess {
  my ($self) = @_;
  if ($self->content =~ m{You should select <a href="(.*)">this link</a> to get the right page}) {
    #print STDERR "following link $1\n";
    $self->follow_link(url => $1);
    return 1;
  } elsif ($self->content =~ m{If your browser is not smart enough to switch back automatically when the computation is over, then you'll have to press the Back button (\d+) time}) {
    my $num_back = $1;
    $self->back() for (1..$num_back);
    $self->reload();
  }
  return 0;
}

sub get {
  my ($self, @args) = @_;
  my $retval = $self->SUPER::get(@args);
  return unless $retval;
  return $self->postprocess || $retval;
}

sub follow_link {
  my ($self, @args) = @_;
  my $retval = $self->SUPER::follow_link(@args);
  return unless $retval;
  return $self->postprocess || $retval;
}

sub submit {
  my ($self, @args) = @_;
  my $retval = $self->SUPER::submit(@args);
  return unless $retval;
  return $self->postprocess || $retval;
}

=over

=item pliant_click(context)

This is a low-level method, that you will not need to use directly.

Context argument is something like "button*0*0..." which is usually an argument
to onClick event for image buttons or names of plain buttons. For example,
consider this pliant code:

  icon "images/next.png" help "Next"
    ...

To click on it, do this

  if ($html =~ m{title="Next"\s+onClick="button_pressed\('(.*?)'\)"}) {
    $retval = $self->{mech}->pliant_click($1);
  }

=cut

sub pliant_click {
  my ($self, $context) = @_;
  $self->form_name('pliant');
  $self->field('_', $context);
  $self->field('_pliant_x',0);
  $self->field('_pliant_y',0);
  return $self->submit;
}

sub _make_request {
  my ($self, $request, @args) = @_;
  my $content = $request->content;
  if ($content) {
    $content =~ s/_pliant_x=0&_pliant_y=0&_=(.*?)(&|$)/_pliant_x=0&_pliant_y=0&$1=$2/;
    $content =~ s{&%2F}{&data%2F}g;
    $request->header('Content-Length', length($content));
    $request->content($content);
  }
  return $self->SUPER::_make_request($request, @args);
}

=item pliant_form()

Fetches WWW::Mechanize::Pliant::Form object associated with current page.
This form object is what you should use to fill the fields on the page.  It also
has a high-level click() method that you should use instead of the 
low-level pliant_click() method described above.

   $mech->get("http://mypliantsite.com");
   $mech->form->set_field("search", "Beads Game");
   $mech->form->click("Search");

=cut

sub pliant_form {
  my ($self) = @_;
  if (!$self->{pliant_form}) {
    $self->{pliant_form} = WWW::Mechanize::Pliant::Form->new($self);
  }
  $self->{pliant_form}->reinit;
  return $self->{pliant_form};
}

=back

=head2 WWW::Mechanize::Pliant::Form

This helper class does some of the dirty work of locating pliant 
fields on the pliant page.

=cut

package WWW::Mechanize::Pliant::Form;
use HTML::Entities qw(decode_entities);

=over

=item new(mech)

The Form object works hand in hand with corresponding mechanize object.

=cut

sub new {
  my ($class, $mech) = @_;
  my $self = {};
  $self->{mech} = $mech;
  bless $self, $class;
  $self->reinit;
  return $self;
}

=item reinit()

This method should be called if the page in the associated mechanize object
has changed.  It is automatically called at the end of click() routine,
so you will most likely never need to call this directly.

=cut

sub reinit {
  my ($self) = @_;
  $self->{fields} = [ $self->{mech}->form('pliant')->param ];
}

=item find_field(pattern)

Tries to find a field in the form object, given a regex.
This doesn't include search over image buttons or standard buttons.
If found returns full name of the field (with all the pliant mangling),
or undef if not found.

=cut

sub find_field {
  my ($self, $regex) = @_;
  my @matches = grep { /$regex/ } @{$self->{fields}};
  return $matches[0];
}

=item set_field(pattern, value)

This is the method that should be used to set the fields in the form.

   $form->set_field('email', 'john@somedomain.com');
   $form->set_field(qr{payment_data.*?card_number}, '4444222233331111');
   ...
   $form->click("Submit Info");

=cut

sub set_field {
  my ($self, $regex, $value) = @_;
  if (my $name = $self->find_field($regex) ) {
    $self->{mech}->form_name('pliant');
    $self->{mech}->field($name, $value);
  }
}

=item click(PATTERN)

This will click on an image button or on a button. It will try to find 
the button using these two regular expressions against the content,

  try1: qr{title="PATTERN"\s+onClick="button_pressed\('(.*?)'\)"}
  try2: qr{name="(button.*?)"\s+value="PATTERN"}

The first attempt is to find an image button with PATTERN in the title field.  
The second attempt is to find a plain button with PATTERN in its caption.

  $form->click('Next');
  $form->click('Buy now');

Since PATTERN is a regular expression, if the name of the button has parenthesis, 
you need to escape them:

  $form->click(qr{delete Greeting Card \(New Baby\)});
  
=back

=cut

sub click {
  my ($self, $regex) = @_;
  my $retval = 0;
  my $content = decode_entities($self->{mech}->content);
  if ($content =~ m{title="$regex"\s+onClick="button_pressed\('(.*?)'\)"}) {
    $retval = $self->{mech}->pliant_click($1);
    $self->reinit;
  } elsif ($content =~ m{name="(button.*?)"\s+value="$regex"}) {
    $retval = $self->{mech}->pliant_click($1);
    $self->reinit;
  }
  return $retval;
}

=pod

=head1 AUTHOR

Boris Reitman <boris.reitman@gmail.com>

=head1 SEE ALSO

WWW::Mechanize,
http://en.wikipedia.org/wiki/Pliant

=cut

1;
