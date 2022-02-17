web: npx live-server playbook/build/site
watcher: npx chokidar "*" "**/*" "../teak-unity/docs/**/*" "../teak-ios/docs/**/*" "../teak-android/docs/**/*" "../teak-sdk-reference/**/*" --ignore "/build|public/" -c "npx gulp bundle && npx antora playbook/antora-playbook-dev.yml"
