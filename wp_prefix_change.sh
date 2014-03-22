#!/bin/bash

echo "Enter the path to your WordPress install: "
read WP_CONFIG_PATH

# Quick hack to make PHP var available
table_prefix='$table_prefix'

DB_DETAILS=(`/usr/bin/env php <<EOL
<?php
require "$WP_CONFIG_PATH/wp-load.php";
echo DB_USER . "\n";
echo DB_PASSWORD . "\n";
echo DB_NAME . "\n";
echo DB_HOST . "\n";
echo $table_prefix;
?>
EOL`)

if [ ${#DB_DETAILS[@]} -lt 5 ]; then
	echo "Could not retrieve config values from your WordPress install."
	exit;
fi

echo "Retrieved WordPress configuration data OK!"

DB_USER=${DB_DETAILS[0]}
DB_PASSWORD=${DB_DETAILS[1]}
DB_NAME=${DB_DETAILS[2]}
DB_HOST=${DB_DETAILS[3]}
DB_PREFIX=${DB_DETAILS[4]}

echo "Testing connection to the database..."
TABLES=(`/usr/bin/env mysql -u $DB_USER --password=$DB_PASSWORD -h $DB_HOST -e "SHOW TABLES IN $DB_NAME"`)

if [ ${#TABLES[@]} -eq 0 ]; then
	echo "Could not connect to database"
	exit
fi

echo "Connected OK!"

echo "Back up database and wp-config? (HIGHLY RECOMMENDED)"
read BACKUP_YESNO

if [ ${BACKUP_YESNO:0:1} == 'y' ] || [ ${BACKUP_YESNO:0:1} == 'Y' ]; then

	mysqldump -u $DB_USER --password=$DB_PASSWORD $DB_NAME | gzip -c > ./$DB_NAME.sql.gz

	BACKUP_RESULT=${PIPESTATUS[0]}

#	Thanks, http://scratching.psybermonkey.net/2011/01/bash-how-to-check-exit-status-of-pipe.html
	
	if [ $BACKUP_RESULT -ne "0" ]; then
		echo "There was an error performing the backup. Error code was $BACKUP_RESULT"
		exit
	fi
	
	cp $WP_CONFIG_PATH/wp-config.php ./$DB_NAME-wp-config.php
	
fi

echo "Backup completed OK!"

echo "Enter the new database prefix"
read NEW_PREFIX

if [ ${NEW_PREFIX:-1} != '_' ]; then
	NEW_PREFIX+="_"
fi

if [ $NEW_PREFIX == $DB_PREFIX ]; then
	echo "The database prefix you entered is already the active prefix"
	exit
fi

echo "Renaming tables..."

for (( idx=1; idx<${#TABLES[@]}; idx++ ))
do
	TABLE_NAME=${TABLES[$idx]//$DB_PREFIX/$NEW_PREFIX}
	echo "Renaming: $DB_NAME.${TABLES[$idx]} to $DB_NAME.$TABLE_NAME"
	mysql -u $DB_USER --password=$DB_PASSWORD -h $DB_HOST -e "RENAME TABLE $DB_NAME.${TABLES[$idx]} TO $DB_NAME.$TABLE_NAME;"
done

OPTABLE="$NEW_PREFIX"
OPTABLE+="options"
UMTABLE="$NEW_PREFIX"
UMTABLE+="usermeta"

echo "Updating options and usermeta tables..."

mysql -u $DB_USER --password=$DB_PASSWORD -h $DB_HOST -e "UPDATE $DB_NAME.$OPTABLE SET option_name = REPLACE(option_name,'$DB_PREFIX','$NEW_PREFIX');"
mysql -u $DB_USER --password=$DB_PASSWORD -h $DB_HOST -e "UPDATE $DB_NAME.$UMTABLE SET meta_key = REPLACE(meta_key,'$DB_PREFIX','$NEW_PREFIX');"

echo "Changing the prefix in the wp-config.php file..."

WP_CONFIG_FILE="$WP_CONFIG_PATH""/wp-config.php"

sed -i --follow-symlinks -e "s/$DB_PREFIX/$NEW_PREFIX/g" $WP_CONFIG_FILE


echo "Done!"
