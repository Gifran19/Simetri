@echo off
set "JAVA_HOME=C:\Program Files\Android\Android Studio\jbr"
set "PATH=C:\Program Files\Android\Android Studio\jbr\bin;%PATH%"
set "NO_UPDATE_NOTIFIER=1"
firebase emulators:exec --config ../../firebase.json --project simetri-app --only auth,functions,database "npm test"

