#=====================================================================
# LX-Office ERP
# Copyright (C) 2004
# Based on SQL-Ledger Version 2.1.9
# Web http://www.lx-office.org
#
#=====================================================================
# SQL-Ledger Accounting
# Copyright (c) 2002
#
#  Author: Dieter Simader
#   Email: dsimader@sql-ledger.org
#     Web: http://www.sql-ledger.org
#
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
#======================================================================
#
# Payment module
#
#======================================================================

use SL::CP;
use SL::IS;
use SL::IR;
use SL::AR;
use SL::AP;
use strict;
#use warnings;

require "bin/mozilla/arap.pl";
require "bin/mozilla/common.pl";

our ($form, %myconfig, $lxdebug, $locale, $auth);

1;

# end of main

sub payment {
  $lxdebug->enter_sub();

  $auth->assert('cash');

  my (@curr);

  $form->{ARAP} = ($form->{type} eq 'receipt') ? "AR" : "AP";
  $form->{arap} = lc $form->{ARAP};

  # setup customer/vendor selection for open invoices
  if ($form->{all_vc}) {
    # Dieser Zweig funktioniert derzeit NIE. Ggf. ganz raus oder
    # alle offenen Zahlungen wieder korrekt anzeigen. jb 12.10.2010
    $form->all_vc(\%myconfig, $form->{vc}, $form->{ARAP});
  } else {
    CP->get_openvc(\%myconfig, \%$form);
  }
  # Auswahlliste für vc zusammenbauen
  # Erweiterung für schliessende option und erweiterung um value
  # für bugfix 1771 (doppelte Leerzeichen werden nicht 'gepostet')
  $form->{"select$form->{vc}"} = "";

  if ($form->{"all_$form->{vc}"}) {
    # s.o. jb 12.10.2010
    $form->{"$form->{vc}_id"} = $form->{"all_$form->{vc}"}->[0]->{id};
    map { $form->{"select$form->{vc}"} .= "<option value=\"$_->{name}--$_->{id}\">$_->{name}--$_->{id}</option>\n" }
      @{ $form->{"all_$form->{vc}"} };
  }

  CP->paymentaccounts(\%myconfig, \%$form);

  # Standard Konto für Umlaufvermögen
  my $accno_arap = IS->get_standard_accno_current_assets(\%myconfig, \%$form);
  # Entsprechend präventiv die Auswahlliste für Kontonummer 
  # auch mit value= zusammenbauen (s.a. oben bugfix 1771)
  # Wichtig: Auch das Template anpassen, damit hidden input korrekt die "
  # escaped.
  $form->{selectaccount} = "";
  $form->{"select$form->{ARAP}"} = "";

  map { $form->{selectaccount} .= "<option value=\"$_->{accno}--$_->{description}\">$_->{accno}--$_->{description}</option>\n";
        $form->{account}        = "$_->{accno}--$_->{description}" if ($_->{accno} eq $accno_arap) } @{ $form->{PR}{"$form->{ARAP}_paid"} };

  # Braucht man das hier überhaupt? Erstmal auskommentieren .. jan 18.12.2010
  #  map {
  #    $form->{"select$form->{ARAP}"} .=
  #      "<option>$_->{accno}--$_->{description}\n"
  #  } @{ $form->{PR}{ $form->{ARAP} } };
  # ENDE LOESCHMICH in 2012

  # currencies
  # oldcurrency ist zwar noch hier als fragment enthalten, wird aber bei
  # der aktualisierung der form auch nicht mitübernommen. das konzept
  # old_$FOO habe ich auch noch nicht verstanden ...
  # Ok. Wenn currency übernommen werden, dann in callback-string über-
  # geben und hier reinparsen, oder besser multibox oder html auslagern?
  # Antwort: form->currency wird mit oldcurrency oder curr[0] überschrieben
  # Wofür macht das Sinn?
  @curr = split(/:/, $form->{currencies});
  chomp $curr[0];
  $form->{defaultcurrency} = $form->{currency} = $form->{oldcurrency} =
    $curr[0];

  # Entsprechend präventiv die Auswahlliste für Währungen 
  # auch mit value= zusammenbauen (s.a. oben bugfix 1771)
  $form->{selectcurrency} = "";
  map { $form->{selectcurrency} .= "<option value=\"$_\">$_</option>\n" } @curr;


  &form_header;
  &form_footer;

  $lxdebug->leave_sub();
}

sub form_header {
  $lxdebug->enter_sub;

  $auth->assert('cash');

  my ($vc, $arap, $exchangerate);
  my ($onload);

  if ($form->{ $form->{vc} } eq "") {
    map { $form->{"addr$_"} = "" } (1 .. 4);
  }
  # bugfix 1771
  # geändert von <option>asdf--2929
  # nach:
  #              <option value="asdf--2929">asdf--2929</option>
  # offen: $form->{ARAP} kann raus?
  for my $item ($form->{vc}, "account", "currency", $form->{ARAP}) {
    $form->{"select$item"} =~ s/ selected//;
    $form->{"select$item"} =~ s/option value="\Q$form->{$item}\E">\Q$form->{$item}\E/option selected value="$form->{$item}">$form->{$item}/;
  }

  $vc =
    ($form->{"select$form->{vc}"})
    ? qq|<select name=$form->{vc}>$form->{"select$form->{vc}"}\n</select>|
    : qq|<input name=$form->{vc} size=35 value="$form->{$form->{vc}}">|;

  $form->{openinvoices} = $form->{all_vc} ? "" : 1;

  # $locale->text('AR')
  # $locale->text('AP')

  $form->header;

  $arap = lc $form->{ARAP};
  $onload = qq|focus()|;
  $onload .= qq|;setupDateFormat('|. $myconfig{dateformat} .qq|', '|. $locale->text("Falsches Datumsformat!") .qq|')|;
  $onload .= qq|;setupPoints('|. $myconfig{numberformat} .qq|', '|. $locale->text("wrongformat") .qq|')|;

  print $::form->parse_html_template('cp/form_header', {
    is_customer => $form->{vc}   eq 'customer',
    is_receipt  => $form->{type} eq 'receipt',
    onload      => $onload,
    arap        => $arap,
    vccontent   => $vc,
  });

  $lxdebug->leave_sub;
}

sub list_invoices {
  $::lxdebug->enter_sub;
  $::auth->assert('cash');

  my @columns = qw(amount due paid invnumber id transdate checked);
  my (@invoices, %total);
  for my $i (1 .. $::form->{rowcount}) {
    push @invoices, +{ map { $_ => $::form->{"$_\_$i"} } @columns };
    $total{$_} += $invoices[-1]{$_} = $::form->parse_amount(\%::myconfig, $invoices[-1]{$_}) for qw(amount due paid);
  }

  print $::form->parse_html_template('cp/invoices', {
    invoices => \@invoices,
    totals   => \%total,
  });

  $::lxdebug->leave_sub;
}

sub form_footer {
  $::lxdebug->enter_sub;
  $::auth->assert('cash');

  print $::form->parse_html_template('cp/form_footer');

  $::lxdebug->leave_sub;
}

sub update {
  $lxdebug->enter_sub();

  $auth->assert('cash');

  my ($new_name_selected) = @_;

  my ($buysell, $newvc, $updated, $exchangerate, $amount);

  if ($form->{vc} eq 'customer') {
    $buysell = "buy";
  } else {
    $buysell = "sell";
  }

  # if we switched to all_vc
  # funktioniert derzeit nicht 12.10.2010 jb
  if ($form->{all_vc} ne $form->{oldall_vc}) {

    $form->{openinvoices} = ($form->{all_vc}) ? 0 : 1;

    $form->{"select$form->{vc}"} = "";

    if ($form->{all_vc}) {
      $form->all_vc(\%myconfig, $form->{vc}, $form->{ARAP});

      if ($form->{"all_$form->{vc}"}) {
        map {
          $form->{"select$form->{vc}"} .=
            "<option>$_->{name}--$_->{id}\n"
        } @{ $form->{"all_$form->{vc}"} };
      }
    } else {  # ab hier wieder ausgeführter code (s.o.):
      CP->get_openvc(\%myconfig, \%$form);

      if ($form->{"all_$form->{vc}"}) {
        $newvc =
          qq|$form->{"all_$form->{vc}"}[0]->{name}--$form->{"all_$form->{vc}"}[0]->{id}|;
        map {
          $form->{"select$form->{vc}"} .=
            "<option>$_->{name}--$_->{id}\n"
        } @{ $form->{"all_$form->{vc}"} };
      }

      # if the name is not the same
      if ($form->{"select$form->{vc}"} !~ /$form->{$form->{vc}}/) {
        $form->{ $form->{vc} } = $newvc;
      }
    }
  }

  # search by invoicenumber, 
  if ($form->{invnumber}) { 
    $form->{open} ='Y'; # nur die offenen rechnungen
    if ($form->{ARAP} eq 'AR'){

      # ar_transactions automatically searches by $form->{customer_id} or else
      # $form->{customer} if available, and these variables will always be set
      # when we have a dropdown field rather than an input field, so we have to
      # empty these values first
      $form->{customer_id} = '';
      $form->{customer} = '';
      AR->ar_transactions(\%myconfig, \%$form);

      # if you search for invoice '11' ar_transactions will also match invoices
      # 112, 211, ... due to the LIKE

      # so there is now an extra loop that tries to match the invoice number
      # exactly among all returned results, and then passes the customer_id instead of the name
      # because the name may not be unique

      my $found_exact_invnumber_match = 0;
      foreach my $i ( @{ $form->{AR} } ) {
        next unless $i->{invnumber} eq $form->{invnumber};
        # found exactly matching invnumber
        $form->{$form->{vc}} = $i->{name};
        $form->{customer_id} = $i->{customer_id};
        #$form->{"old${form->{vc}"} = $i->{customer_id};
        $found_exact_invnumber_match = 1;
      };

      unless ( $found_exact_invnumber_match ) {
        # use first returned entry, may not be the correct one if invnumber doesn't
        # match uniquely
        $form->{$form->{vc}} = $form->{AR}[0]{name};
        $form->{customer_id} = $form->{AR}[0]{customer_id};
      };
    } else {
      # s.o. nur für zahlungsausgang
      AP->ap_transactions(\%myconfig, \%$form);
      $form->{$form->{vc}} = $form->{AP}[0]{name};
    }
  }

  # determine customer/vendor
  if ( $form->{customer_id} and $form->{invnumber} ) {
    # we already know the exact customer_id, so fill $form with customer data
    IS->get_customer(\%myconfig, \%$form);
    $updated = 1;
  } else {
    # check_name is called with "customer" or "vendor" and otherwise uses contents of $form
    # check_name also runs get_customer/get_vendor
    $updated = &check_name($form->{vc});
  };

  if ($new_name_selected || $updated) {
    # get open invoices from ar/ap using $form->{vc} and a.${vc}_id, i.e. customer_id
    CP->get_openinvoices(\%myconfig, \%$form);
    ($newvc) = split /--/, $form->{ $form->{vc} };
    $form->{"old$form->{vc}"} = qq|$newvc--$form->{"$form->{vc}_id"}|;
    $updated = 1;
  }

  if ($form->{currency} ne $form->{oldcurrency}) {
    $form->{oldcurrency} = $form->{currency};
    if (!$updated) {
      CP->get_openinvoices(\%myconfig, \%$form);
      $updated = 1;
    }
  }

  $form->{forex}        = $form->check_exchangerate( \%myconfig, $form->{currency}, $form->{datepaid}, $buysell);
  $form->{exchangerate} = $form->{forex} if $form->{forex};

  $amount = $form->{amount} = $form->parse_amount(\%myconfig, $form->{amount});

  if ($updated) {
    $form->{rowcount} = 0;

    $form->{queued} = "";

    my $i = 0;
    foreach my $ref (@{ $form->{PR} }) {
      $i++;
      $form->{"id_$i"}        = $ref->{id};
      $form->{"invnumber_$i"} = $ref->{invnumber};
      $form->{"transdate_$i"} = $ref->{transdate};
      $ref->{exchangerate} = 1 unless $ref->{exchangerate};
      $form->{"amount_$i"} = $ref->{amount} / $ref->{exchangerate};
      $form->{"due_$i"}    =
        ($ref->{amount} - $ref->{paid}) / $ref->{exchangerate};
      $form->{"checked_$i"} = "";
      $form->{"paid_$i"}    = "";

      # need to format
      map {
        $form->{"${_}_$i"} =
          $form->format_amount(\%myconfig, $form->{"${_}_$i"}, 2)
      } qw(amount due);

    }
    $form->{rowcount} = $i;
  }

  # recalculate

  # Modified from $amount = $form->{amount} by J.Zach to update amount to total
  # payment amount in Zahlungsausgang
  $amount = 0;
  for my $i (1 .. $form->{rowcount}) {

    map {
      $form->{"${_}_$i"} =
        $form->parse_amount(\%myconfig, $form->{"${_}_$i"})
    } qw(amount due paid);

    if ($form->{"checked_$i"}) {

      # calculate paid_$i
      if (!$form->{"paid_$i"}) {
        $form->{"paid_$i"} = $form->{"due_$i"};
      }

      # Modified by J.Zach, see abovev
      $amount += $form->{"paid_$i"};

    } else {
      $form->{"paid_$i"} = "";
    }

    map {
      $form->{"${_}_$i"} =
        $form->format_amount(\%myconfig, $form->{"${_}_$i"}, 2)
    } qw(amount due paid);

  }

  # Line added by J.Zach, see above
  $form->{amount}=$amount;

  &form_header;
  &list_invoices;
  &form_footer;

  $lxdebug->leave_sub();
}

sub post {
  $lxdebug->enter_sub();

  $auth->assert('cash');

  &check_form;

  if ($form->{currency} ne $form->{defaultcurrency}) {
    $form->error($locale->text('Exchangerate missing!'))
      unless $form->{exchangerate};
  }

  # Beim Aktualisieren wird das Konto übernommen
  # und jetzt auch Beleg und Datum
  $form->{callback} = "cp.pl?action=payment&vc=$form->{vc}&type=$form->{type}&account=$form->{account}&$form->{currency}" .
                      "&datepaid=$form->{datepaid}&source=$form->{source}";

  my $msg1 = $::form->{type} eq 'receipt' ? $::locale->text("Receipt posted!") : $::locale->text("Payment posted!");
  my $msg2 = $::form->{type} eq 'receipt' ? $::locale->text("Cannot post Receipt!") : $::locale->text("Cannot post Payment!");

  # Die Nachrichten (Receipt posted!) werden nicht angezeigt.
  # Entweder wieder aktivieren oder komplett rausnehmen
  $form->redirect($msg1) if (CP->process_payment(\%::myconfig, $::form));
  $form->error($msg2);

  $lxdebug->leave_sub();
}

sub check_form {
  $lxdebug->enter_sub();

  $auth->assert('cash');

  my ($closedto, $datepaid, $amount);

  &check_name($form->{vc});

  if ($form->{currency} ne $form->{oldcurrency}) {
    &update;
    ::end_of_request();
  }
  $form->error($locale->text('Date missing!')) unless $form->{datepaid};
  my $selected_check = 1;
  for my $i (1 .. $form->{rowcount}) {
    if ($form->{"checked_$i"}) {
      if ($form->parse_amount(\%myconfig, $form->{"paid_$i"}, 2) <= 0) { # negativen Betrag eingegeben
          $form->error($locale->text('Amount has to be greater then zero! Wrong row number: ') . $i);
      }
        undef($selected_check);
        # last; # ich muss doch über alle buchungen laufen, da ich noch
        # die freitext-eingabe der werte prüfen will
    }
  }
  $form->error($locale->text('No transaction selected!')) if $selected_check;

  $closedto = $form->datetonum($form->{closedto}, \%myconfig);
  $datepaid = $form->datetonum($form->{datepaid}, \%myconfig);

  $form->error($locale->text('Cannot process payment for a closed period!'))
    if ($form->date_closed($form->{"datepaid"}, \%myconfig));

  $amount = $form->parse_amount(\%myconfig, $form->{amount});
  $form->{amount} = $amount;

  for my $i (1 .. $form->{rowcount}) {
    if ($form->parse_amount(\%myconfig, $form->{"paid_$i"})) {
      $amount -= $form->parse_amount(\%myconfig, $form->{"paid_$i"});

      push(@{ $form->{paid}      ||= [] }, $form->{"paid_$i"});
      push(@{ $form->{due}       ||= [] }, $form->{"due_$i"});
      push(@{ $form->{invnumber} ||= [] }, $form->{"invnumber_$i"});
      push(@{ $form->{invdate}   ||= [] }, $form->{"transdate_$i"});
    }
  }

  if ($form->round_amount($amount, 2) != 0) {
    push(@{ $form->{paid} }, $form->format_amount(\%myconfig, $amount, 2));
    push(@{ $form->{due} }, $form->format_amount(\%myconfig, 0, "0"));
    push(@{ $form->{invnumber} },
         ($form->{ARAP} eq 'AR')
         ? $locale->text('Deposit')
         : $locale->text('Prepayment'));
    push(@{ $form->{invdate} }, $form->{datepaid});
  }

  $lxdebug->leave_sub();
}
