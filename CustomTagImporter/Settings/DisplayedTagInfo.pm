#
# Custom Tag Importer
#
# (c) 2022 AF
#
# GPLv3 license
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <https://www.gnu.org/licenses/>.
#

package Plugins::CustomTagImporter::Settings::DisplayedTagInfo;

use strict;
use warnings;
use utf8;

use base qw(Plugins::CustomTagImporter::Settings::BaseSettings);

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Misc;
use Slim::Utils::Strings;

my $prefs = preferences('plugin.customtagimporter');
my $log = logger('plugin.customtagimporter');

my $plugin;

sub new {
	my $class = shift;
	$plugin = shift;
	$class->SUPER::new($plugin);
}

sub name {
	return Slim::Web::HTTP::CSRF->protectName('PLUGIN_CUSTOMTAGIMPORTER_DISPLAYEDTAGINFO');
}

sub page {
	return Slim::Web::HTTP::CSRF->protectURI('plugins/CustomTagImporter/settings/displayedtaginfo.html');
}

sub currentPage {
	return name();
}

sub pages {
	my %page = (
		'name' => name(),
		'page' => page(),
	);
	my @pages = (\%page);
	return \@pages;
}

sub prefs {
	return ($prefs);
}

sub handler {
	my ($class, $client, $paramRef) = @_;
	my $result = undef;
	my $maxItemNum = 60;

	# Save buttons config
	if ($paramRef->{saveSettings}) {
		my %configmatrix;
		my %searchstringDone;

		for (my $n = 0; $n <= $maxItemNum; $n++) {
			my $songdetailsmenuenabled = $paramRef->{"pref_songdetailsmenuenabled_$n"} // undef;
			my $titleformatenabled = $paramRef->{"pref_titleformatenabled_$n"} // undef;
			next if (!$songdetailsmenuenabled && !$titleformatenabled);

			my $customtag = $paramRef->{"pref_customtag_$n"};

			my $songdetailsmenuname = trim_leadtail($paramRef->{"pref_songdetailsmenuname_$n"} // '');
			$songdetailsmenuname =~ s/[\$#@~!&*\[\];:?^`\\\/]+//g;

			my $songdetailsmenuposition = $paramRef->{"pref_songdetailsmenuposition_$n"};

			$configmatrix{$customtag} = {
				'customtag' => $customtag,
				'songdetailsmenuenabled' => $songdetailsmenuenabled,
				'songdetailsmenuname' => $songdetailsmenuname,
				'songdetailsmenuposition' => $songdetailsmenuposition,
				'titleformatenabled' => $titleformatenabled,
			};
		}
		$prefs->set('customtagconfigmatrix', \%configmatrix);
		$paramRef->{'customtagconfigmatrix'} = \%configmatrix;
		main::DEBUGLOG && $log->is_debug && $log->debug('SAVED VALUES = '.Data::Dump::dump(\%configmatrix));

		$result = $class->SUPER::handler($client, $paramRef);
	}

	### push to settings page
	my $availableCustomTags = Plugins::CustomTagImporter::Plugin::getAvailableCustomTags();
	main::DEBUGLOG && $log->is_debug && $log->debug('available custom tags = '.Data::Dump::dump($availableCustomTags));


	my $configmatrix = $prefs->get('customtagconfigmatrix');
	my @webconfiglist = ();

	foreach my $thisCustomTag (sort keys %{$availableCustomTags}) {
		main::DEBUGLOG && $log->is_debug && $log->debug('thisCustomTag = '.$thisCustomTag);
		push (@webconfiglist, {
			'customtag' => $thisCustomTag,
			'songdetailsmenuenabled' => $configmatrix->{$thisCustomTag}->{'songdetailsmenuenabled'} // undef,
			'songdetailsmenuname' => $configmatrix->{$thisCustomTag}->{'songdetailsmenuname'} ? $configmatrix->{$thisCustomTag}->{'songdetailsmenuname'} : ucfirst(lc($thisCustomTag)),
			'songdetailsmenuposition' => $configmatrix->{$thisCustomTag}->{'songdetailsmenuposition'},
			'titleformatenabled' => $configmatrix->{$thisCustomTag}->{'titleformatenabled'} // undef,
		});
	}

	$paramRef->{'customtagconfigmatrix'} = \@webconfiglist;
	$paramRef->{itemcount} = scalar @webconfiglist;
	main::DEBUGLOG && $log->is_debug && $log->debug('page list = '.Data::Dump::dump($paramRef->{'customtagconfigmatrix'}));

	$result = $class->SUPER::handler($client, $paramRef);

	return $result;
}

sub trim_all {
	my ($str) = @_;
	$str =~ s/ //g;
	return $str;
}

sub trim_leadtail {
	my ($str) = @_;
	$str =~ s{^\s+}{};
	$str =~ s{\s+$}{};
	return $str;
}

sub is_integer {
	defined $_[0] && $_[0] =~ /^[+-]?\d+$/;
}

1;
