# pcapvault
pcapvault persistently captures traffic on a given interface
 the captured pcaps are gzipped and organized into a structured file system based on date and time, in 60 second intervals
  
  additonal features:
  
  cleanup - allows deleting pcaps from the vault based on date and time, or a full cleanup
  
  export -  allow exporting pcaps from the vault based on data and time, or a full export
            can export from the vault directly in 60 second intervals, or in merged summary format

  external commands used
    date, tail, gzip, ls, tee, wc, tcpdump, mergecap, editcap, mv, rm, cp, awk, mkdir, touch, du, grep
    most of these should be preinstalled, but you may need to run your distros equivalent of 
    sudo yum install -y gzip tcpdump wireshark

pcapvault is just a bash script, so no compiling or anything

#to run, just download the script
chmod +x pcv.sh
#there is only 1 config setting that is required to be edited,
  #the _TCPDUMP_INTERFACE setting
#the interface name should match the names as listed by tcpdump
tcpdump --list-interfaces
#edit with nano or your editor of choic
nano pcv.sh
#edit the _TCPDUMP_INTERFACE setting to match your interface name
_TCPDUMP_INTERFACE="enp4s0f0"

pcapvault does not prep your interface for capture
your interface must already be configure for capturing

once you are ready to start capturing
#create a vault
./pcv.sh -setup testvault
#start the capture
./pcv.sh -start testvault
#verify capturing and processing are working
./pcv.sh -list vaults

when you are ready to stop capturing
./pcv.sh -stop testvault

pcapvault --help
pcapvault -setup --help                                                         # setup help
  pcapvault -setup vault [alphanumeric]                                           # builds dir structure for named vault
  pcapvault -setup vault [alphanumeric] [interface]                               # builds dir structure for named vault, with interface
pcapvault -list --help                                                          # list help
  pcapvault -list vault                                                           # lists all vaults
pcapvault -start --help                                                         # start help
  pcapvault -start [vaultname]                                                    # start tcpdump and processing for named vault, using the default interface
  pcapvault -start [vaultname] [interface]                                        # start tcpdump and processing for named vault, using the named interface
pcapvault -stop --help                                                          # stop capturing and processing pcaps
  pcapvault -stop [vaultname]                                                     # stops tcpdump and processing for named vault
pcapvault -cleanup --help                                                       # cleanup help
  pcapvault -cleanup [vault] [full]                                               # deletes a vault's full directory structure
  pcapvault -cleanup [vault] [from_date] [to_date]                                # deletes pcaps in range from vault
pcapvault -export --help                                                        # export help
  pcapvault -export [vault] [from_date] [to_date]                                 # export pcaps in range from vault
  pcapvault -export [vault] [from_date] [to_date] <summary_size>                  # summary pcap file size limit in MB [range 10...4000], default=1000
  pcapvault -export [vault] [from_date] [to_date] <summary_size> <summary-only>   # the export will only contain summary pcaps
  pcapvault -export [vault] [from_date] [to_date] <no-summary>                    # the export will only contain copies of the archive pcaps, no summary pcaps
pcapvault -ts --help                                                            # troubleshooting
  pcapvault -ts date [YYYY<->YYYY-MM-DDTHH:MM:SS±TZNE]                            # checks to see if a date input is valid
  pcapvault -ts date examples                                                     # prints acceptable date input examples
