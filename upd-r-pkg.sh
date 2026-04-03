#!/bin/bash

SELF="$0"
BASE_DIR="$(pwd)"
BUILD_DB="$BASE_DIR/r-packages_db"
BUILD_DIR="$BASE_DIR/packages"
REPO_DIR="$BASE_DIR/repo"
REPO_DB="$REPO_DIR/r-packages.db.tar.zst"
DEPLOY_LIST="$BASE_DIR/deployed.txt"

check_root () {
	if [ ! "$(whoami)" = "root" ]; then
		echo "Error: must be run as root" >&2
		exit
	fi
}

################
# R Operations #
################

get_script () {
	if [[ "$SELF" =~ "upd-r-pkg" ]]; then
		sed '1,/^#EOF$/d' < "$SELF" | tar xzf - -O "$1"
	else
		cat $1
	fi
}

get_packages () {
	sqlite3 -list "$BUILD_DB" \
		"SELECT * \
		FROM package_info;" 2> /dev/null |
		Rscript <(get_script get-updates.R) |
		sqlite3 "$BUILD_DB"
}

print_PKGBUILD () {
	local package="${1:?Must specify a package}"
	local version="${2:?Must provide the package version string}"
	sqlite3 -list "$BUILD_DB" \
		"SELECT * \
		FROM package_info \
		WHERE Package = '$package' \
		AND Version = '$version' \
		ORDER BY iteration DESC \
		LIMIT 1;" 2> /dev/null |
		Rscript <(get_script output-pkgbuild.R)
}

#################
# DB Operations #
#################

initialize_db () {
	sqlite3 -list "$BUILD_DB" \
		"CREATE TABLE IF NOT EXISTS packages \
		(name TEXT, \
		version TEXT, \
		held BOOLEAN DEFAULT 0);" 2> /dev/null
	sqlite3 -list "$BUILD_DB" \
		"CREATE TABLE IF NOT EXISTS r_depends \
		(parent_name TEXT, \
		depend_name TEXT, \
		min_version TEXT);" 2> /dev/null
	sqlite3 -list "$BUILD_DB" \
		"CREATE TABLE IF NOT EXISTS package_info \
		(Package TEXT, \
		Version TEXT, \
		Title TEXT, \
		License TEXT, \
		Imports TEXT, \
		Suggests TEXT, \
		MD5sum TEXT, \
		iteration INT);" 2> /dev/null

	# Get initial update
	while read -r pkg; do
		sqlite3 -list "$BUILD_DB" \
			"INSERT INTO package_info (Package) \
			VALUES ('$pkg')"
	done < "$DEPLOY_LIST"
	get_packages

	# Set iterations to 1
	sqlite3 -list "$BUILD_DB" \
		"UPDATE package_info \
		SET iteration = 1;" 2> /dev/null

	# Add packages to the package table
	while IFS='|' read -r pkg ver; do
		sqlite3 -list "$BUILD_DB" \
			"INSERT INTO packages (name, version) \
			VALUES ('$pkg', '$ver');" 2> /dev/null
	done < <(sqlite3 -list "$BUILD_DB" \
			"SELECT Package, Version \
			FROM package_info WHERE Package = $pkg;")

	# Update dependencies
	while IFS= read -r pkg; do
		update_depends "$pkg"
	done < <(get_distinct_packages)
}

get_depends () {
	local package="${1:?Must specify a package}"
	sqlite3 -list "$BUILD_DB" \
		"SELECT depend_name FROM r_depends \
		WHERE parent_name = $package;"
}

update_depends () {
	local package="${1:?Must specify a package}"

	# Clean out all previous dependencies
	sqlite3 -list "$BUILD_DB" \
		"DELETE FROM r_depends \
		WHERE parent_name = '$package';" 2> /dev/null

	{
		echo "INSERT INTO r_depends \
			(parent_name, depend_name, min_version) \
			VALUES"; 
		while IFS="(" read -r dep ver; do
			echo "('$package', '$dep', '$ver'),"
		done < <(sqlite3 -list "$BUILD_DB" \
				"SELECT Imports \
				FROM package_info \
				WHERE Package = '$package';" 2> /dev/null |
				tr -d " >=)" |
				tr "," "\n");
	} |
		sed '$ s/,$/;/' |
		sqlite3 -list "$BUILD_DB" 2> /dev/null
}

package_exists () {
	local package="${1:?Must specify a package}"
	local lines=$(sqlite3 -list "$BUILD_DB" \
		"SELECT * \
		FROM packages \
		WHERE name = '$package';" 2> /dev/null | wc -l)

	[ "$lines" -eq 1 ]
}

update_db () {
	local package="${1:?Must specify a package}"
	local version="${2:?Must provide the package version string}"

	if package_exists $package; then
		sqlite3 -list "$BUILD_DB" \
			"UPDATE packages SET version = '$version' \
			WHERE name = '$package';" 2> /dev/null
	else
		sqlite3 -list "$BUILD_DB" \
			"INSERT INTO packages \
			(name, version) \
			VALUES ('$package', '$version');" 2> /dev/null
	fi
}

hold () {
	local package="${1:?Must specify a package}"
	local version="${2:?Must provide the package version string}"

	sqlite3 -list "$BUILD_DB" \
		"UPDATE packages \
		SET held = 1, version = '$version' \
		WHERE name = '$package';" 2> /dev/null
}

release () {
	local package="${1:?Must specify a package}"
	local version="${2:?Must provide the package version string}"

	sqlite3 -list "$BUILD_DB" \
		"UPDATE packages \
		SET held = 0, version = '$version' \
		WHERE name = '$package';" 2> /dev/null
}

get_distinct_packages () {
	sqlite3 -list "$BUILD_DB" \
		"SELECT DISTINCT Package \
		FROM package_info;" 2> /dev/null
}

get_newest_version () {
	local package="${1:?Must specify a package}"
	sqlite3 -list "$BUILD_DB" \
		"SELECT * \
		FROM package_info \
		WHERE Package = '$package' \
		ORDER BY iteration DESC \
		LIMIT 1;" 2> /dev/null
}

update_package_iterations () {
	for pkg in $(get_distinct_packages); do
		echo "UPDATE package_info \
			SET iteration = \
				(SELECT MAX(iteration) \
				FROM package_info \
				WHERE Package = '$pkg') + 1 \
			WHERE Package = '$pkg' \
			AND iteration IS NULL;"
	done | sqlite3 -list "$BUILD_DB" 2> /dev/null
}

is_not_current () {
	local package="${1:?Must specify a package}"
	local ver="${2:?Must specify a version}"
	local oldver="$(sqlite3 -list "$BUILD_DB" \
		"SELECT version \
		FROM packages \
		WHERE name = '$package' \
		LIMIT 1;")"

	[ ! "$ver" = "$oldver" ]
}

is_held () {
	local package="${1:?Must specify a package}"
	local held="$(sqlite3 -list "$BUILD_DB" \
		"SELECT held \
		FROM packages \
		WHERE name = '$package' \
		LIMIT 1;")"

	[ ! "$held" = "0" ]
}

######################
# Package Operations # 
######################

repository_setup () {
	# Make directories
	mkdir -p "$REPO_DIR"
	mkdir -p "$BUILD_DIR"
	pushd "$BUILD_DIR" > /dev/null

	# Initialize package info database
	initialize_db

	# Setup git repository, including remotes
	pushd "$REPO_DIR" > /dev/null
	git init
	git remote add all "$1"
	shift
	while [ "$#" -gt 0 ]; do
		git remote set-url --add --push origin "$1"
		shift
	done
	git add "$REPO_DB" "$REPO_DB.sig"
	git push all

	# Reset directory
	popd > /dev/null; popd > /dev/null
}

deploy () {
	local package="${1:?Must specify a package}"
	shift # Do this to allow for options to be passed to pacman
	
	# Early exit if held
	if is_held "$package"; then
		return 0
	fi

	# Find version
	local version="$(sqlite3 -list "$BUILD_DB" \
		"SELECT version \
		FROM packages \
		WHERE name = '$package';")"

	# Get PKGBUILD
	update_depends "$package"
	pkgbuild="$(print_PKGBUILD "$package" "$version")"

	# Deploy all dependencies
	for depend in "$(get_depends "$package")"; do
		deploy "$depend" --asdeps
	done

	# Now we can publish our changes
	printf "%s" "$pkgbuild" > "$BUILD_DIR/$package.PKGBUILD"

	# Commit and push with git
	message="Updated r-$package to version $version"
	if ! git add "$BUILD_DIR/$package.PKGBUILD" &&
			git commit -m "$message" &&
			git push --all; then
		# Abort if we can't commit the changes
		printf "Failed to deploy %s-%s\n" "$package" "$version"
		git reset -q --hard HEAD
		return 1
	fi

	commit="$(git rev-parse --short HEAD)"

	update_db "$package" "$version"
	if is_not_current "$package" "$version"; then
		# Update if existing package is found and is not current
		sqlite3 -list "$BUILD_DB" \
			"UPDATE packages \
			SET version = '$version', \
			WHERE name = '$package'"
	else
		# Otherwise we add it to the proper tables
		sqlite3 -list "$BUILD_DB" \
			"INSERT INTO packages (name, version) \
			VALUES ('$package', '$version')"
	fi

	return 0
}

deploy_all () {
	while IFS= read -r pkg; do
		deploy "$pkg"
	done < "$DEPLOY_LIST"
}

###############
# Main script #
###############

# Check for external updates to repository
git pull

case "$1" in 
	"hold"
		check_root
		hold "$2"
		;;
	"release")
		check_root
		release "$2"
		;;
	"setup")
		check_root
		repository_setup
		;;
	"help")
		printf "Usage: upd-r-pkg [setup|help] (package)\n\n"
		printf "hold\t\tSets a deployed package to not be "
		printf "automatically updated.\n"
		printf "release\t\tSets a deployed package to be "
		printf "automatically updated.\n"
		printf "setup\t\t\tInitial setup of repository.\n"
		printf "\nUsage with no arguments will simply seek to update "
		printf "all packages.\n"
		;;
	*
		deploy_all
		;;
esac
