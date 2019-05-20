if [ -z "$EFS_ID" ] && [ "$EFS_ID" == "${EFS_ID#fs-}" ] && [ -n "${EFS_ID//[a-fA-F0-9s-]}" ]; then
	echo "ERROR: The provided EFS ID ($EFS_ID) seems to be invalid, refusing to proceed!" >&2
	exit 1
fi

if ! OUTPUT=$(aws efs describe-tags \
        --file-system-id "$EFS_ID" \
        --query 'Tags[?Key == `Status`].Value' \
        --output text)
then
	echo "ERROR: Failed to acquire tags for EFS ID '$EFS_ID', aborting!" >&2
	exit 1
fi

if [ -z "$OUTPUT" ]
then
	VIRTWWW=$(get_gid_from_ad virtwww)
        mkdir -p -m0 /mnt
	mount -t nfs4 -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2 "$EFS_DNS:/" /mnt

        mkdir -p -m755 /mnt/etc{,/nginx{,/sites-{available,enabled}},/php-fpm.d} /mnt/home{,/websites,/users}
        chown -h root:root /mnt/etc{,/nginx{,/sites-{available,enabled}},/php-fpm.d} /mnt/home{,/websites,/users}

	# nginx
	printf '%s\n\t%s\n%s\n' \
		'upstream php_backend {' \
		'server	unix:/run/systemd-socket-proxyd/fastcgi.sock;' \
		'}' \
		> /mnt/etc/nginx/sites-available/php-backend.conf
	chmod 0644 /mnt/etc/nginx/sites-available/php-backend.conf
	chown -h root:root /mnt/etc/nginx/sites-available/php-backend.conf
	ln -snvf ../sites-available/php-backend.conf /mnt/etc/nginx/sites-enabled/000-php-backend.conf

	# Logs configuration
	mkdir -p -m711 /mnt/home/websites/logs
	mkdir -p -m710 /mnt/home/websites/logs/nginx
	chown -h "root:$VIRTWWW" /mnt/home/websites/logs/nginx
	mkdir -p -m710 /mnt/home/websites/logs/php-fpm
	chown -h "root:$VIRTWWW" /mnt/home/websites/logs/php-fpm

	umount /mnt
	aws efs create-tags \
		--file-system-id "$EFS_ID" \
			--tags Key=Status,Value=initialised
fi
