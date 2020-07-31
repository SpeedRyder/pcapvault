# pcapvault
pcapvault persistently captures traffic on a given interface  
    the captured pcaps are gzipped and organized into a structured file system based on date and time, in 60 second intervals
    *$(pwd)/vaults/vaultname/pcaps/archive/yyyy/mm/dd/hh/YYYY-MM-DDTHH:MM:SS±TZNE.pcap.gz*  
    the pcaps are converted from local timezone to UTC +0000 for storage

additonal features:  

cleanup  
allows deleting pcaps from the vault based on date and time, or a full cleanup  

export  
allow exporting pcaps from the vault based on date and time  
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
  #the interface name should match the name as listed by tcpdump  
  tcpdump --list-interfaces  
  #edit with nano or your editor of choice  
  nano pcv.sh  
  #edit the _TCPDUMP_INTERFACE setting to match your interface name  
  _TCPDUMP_INTERFACE="enp4s0f0"  

pcapvault does not prep your interface for capture  
your interface must already be configured for capturing

#once you are ready to start capturing  
#create a vault  
    ./pcv.sh -setup testvault  
#start the capture  
    ./pcv.sh -start testvault  
#verify capturing and processing are working  
    ./pcv.sh -list vaults  

#when you are ready to stop capturing  
./pcv.sh -stop testvault  

    ./pcv.sh --help
    ./pcv.sh -setup --help                                                         # setup help  
      ./pcv.sh -setup vault [alphanumeric]                                           # builds dir structure for named vault  
      ./pcv.sh -setup vault [alphanumeric] [interface]                               # builds dir structure for named vault, with interface  
    ./pcv.sh -list --help                                                          # list help  
      ./pcv.sh -list vault                                                           # lists all vaults  
    ./pcv.sh -start --help                                                         # start help  
      ./pcv.sh -start [vaultname]                                                    # start tcpdump and processing for named vault, using the default interface  
      ./pcv.sh -start [vaultname] [interface]                                        # start tcpdump and processing for named vault, using the named interface  
    ./pcv.sh -stop --help                                                          # stop capturing and processing pcaps  
      ./pcv.sh -stop [vaultname]                                                     # stops tcpdump and processing for named vault  
    ./pcv.sh -cleanup --help                                                       # cleanup help  
      ./pcv.sh -cleanup [vault] [full]                                               # deletes a vault's full directory structure  
      ./pcv.sh -cleanup [vault] [from_date] [to_date]                                # deletes pcaps in range from vault  
    ./pcv.sh -export --help                                                        # export help  
      ./pcv.sh -export [vault] [from_date] [to_date]                                 # export pcaps in range from vault  
      ./pcv.sh -export [vault] [from_date] [to_date] <summary_size>                  # summary pcap file size limit in MB [range 10...4000], default=1000  
      ./pcv.sh -export [vault] [from_date] [to_date] <summary_size> <summary-only>   # the export will only contain summary pcaps  
      ./pcv.sh -export [vault] [from_date] [to_date] <no-summary>                    # the export will only contain copies of the archive pcaps, no summary pcaps  
    ./pcv.sh -ts --help                                                            # troubleshooting  
      ./pcv.sh -ts date [YYYY<->YYYY-MM-DDTHH:MM:SS±TZNE]                            # checks to see if a date input is valid  
      ./pcv.sh -ts date examples                                                     # prints acceptable date input examples  
