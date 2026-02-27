# Backup any website/project to AWS

Shell script to make full backup of your site and upload to AWS.
With autocleaning for old backups. 

1. Clone this repo to /root/ or /home/
```
git clone git@github.com:DmmitryIs/aws-projects-backup.git /root/backup
```

2. Make the backup.sh file executable
```
chmod +x /root/backup/backup.sh
```

3. Install aws cli
```
sudo apt install awscli
```

4. Set AWS key, secret and region
```
aws configure
```

5. Make .env file
```
BUCKET=bucket-name
ALIAS=project1
DAYS_TO_KEEP=20
PROJECT_PATH=/var/www/project
SSL_PATH=/etc/letsencrypt/live
DB_LIST=database:127.0.0.1:user:pass
```

`BUCKET` - aws bucket name\
`ALIAS` - any alias up to you\
`DAYS_TO_KEEP` - days to keep old backups
`PROJECT_PATH` - backup target\
`SSL_PATH` - ssl dir to add to backup (optional)\
`DB_LIST` - possible to use multiple db (comma separated: database:127.0.0.1:user:pass,database1:127.0.0.1:user:pass etc.)
`DB_IGNORE_TABLES` - table1,table2 (comma seprated)

6. Set in crontab
```
crontab -e
```
```
00 01 * * * /bin/bash /root/backup/backup.sh > /tmp/backup.log 2>&1
```

7. Install zip (if not installed) 
```
sudo apt update
```
```
sudo apt install zip unzip -y
```

8. Test manually
```
bash /root/backup/backup.sh
```

