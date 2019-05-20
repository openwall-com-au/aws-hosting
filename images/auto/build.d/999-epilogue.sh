# The following should be the last line of the script
printf 'CODEBUILD_TIME %d second(s)\n' $(($(date '+%s') - $(date -d "@${CODEBUILD_START_TIME:0:10}" '+%s')))
