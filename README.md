# process-utf32logs.ps1

### what does it do? 
It changes files stored on AWS S3 from utf-32 to utf-8, and then puts them back again.

### can i have some non polished instructions?

- Put the buckets that have the log files that you need processing in the config.json file. See example
- The working directory is used for the file processing. 
- Prefix is so we can find the logs. It needs it's last '/' (slash)
- ProcessDate is the date from which to process. 

Run it with :

```powershell
./process-utf32logs.ps1
```
