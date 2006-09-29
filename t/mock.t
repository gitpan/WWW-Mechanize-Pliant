#!/usr/bin/perl
use strict;
use warnings FATAL => 'all';
use Test::More 'no_plan';
use vars qw( $class );
use Test::MockObject;
use File::Slurp;
use HTML::Form;

my $content;

sub get {
  my ($self) = @_;
}

sub _make_request {
  my ($self, $request_, @args) = @_;
}

sub content {
  my ($self) = @_;
  return $content;
}

sub follow_link {
  my ($self) = @_;
  return 1;
}

sub submit {
  my ($self) = @_;
  return 1;
}

sub new {
  my ($class) = @_;
  return bless {}, $class;
}

sub reset_form {
  my ($self) = @_;
  delete $self->{form};
}

sub form {
  my ($self, $name) = @_;
  if (!$self->{form}) {
    $self->{form} = HTML::Form->new($content, "http://somedomain.com");
  }
  return $self->{form};
}

my %fields = ();
sub field {
  my ($self, $key, $val) = @_;
  $fields{$key} = $val;
}

my $mock = Test::MockObject->new;
$mock->fake_module(
  'WWW::Mechanize',
  'get' => \&get,
  'content' => \&content,
  'follow_link' => \&follow_link,
  'submit' => \&submit,
  'new' => \&new,
  'form' => \&form,
  'form_name' => sub {},
  'field' => \&field,
);
use_ok 'WWW::Mechanize::Pliant';

my $mech = WWW::Mechanize::Pliant->new;
$content = read_file "t/files/select_country.html";
$mech->get("http://somedomain.com");

my $form = $mech->pliant_form;
$form->set_field('send_country', "canada");
$form->set_field('rec_country', "canada");
$form->click("Next");
is $fields{_pliant_x}, 0;
is $fields{_pliant_y}, 0;
like $fields{_}, qr{^button};
