#!/bin/bash

###########################
# external commands used #
#########################
#  
# date, tail, gzip, ls, tee, wc, tcpdump, mergecap, editcap, mv, rm, cp, awk, mkdir, touch, du, grep
# most of these should be preinstalled, but you may need to run
#
# sudo yum install -y gzip tcpdump wireshark
#
#########################


#############
### CONFIG #
###########
_config_yes_change(){
  # the default interface tcpdump will listen on
  # ! check with $> tcpdump --list-interfaces
  # ! pcapvault does not prepair the interface for capture
  # ! the interface must already be configured
  _TCPDUMP_INTERFACE="enp4s0f0"
}

_config_maybe_change(){
  # PCV log info
  _PATH_TO_PCV_LOGS="$(pwd)/"
  _PCV_LOG_MAIN="${_PATH_TO_PCV_LOGS}pcv_main.log"
  
  # each log may reach _LOG_MAX_LINES, once met the log is archived to .old
  _LOG_MAX_LINES="100000"
  
  # export summary pcap default max size
  _EXPORT_PCAP_SUMMARY_SIZE="1000"

  # output verbosity
  _VERBOSE_LEVEL="1" # 0 = halt+unknown, 1 = +warn, 2 = +status, 3 = +info

  # console colors
  _C0='\e[0m'       # neutral
  _C1='\e[0;31;40m' # bad
  _C2='\e[0;32;40m' # good
  _C3='\e[0;33;40m' # warn
  _C4='\e[4;35;40m' # title
  _C5='\e[4;97;40m' # heading
  _C6='\e[8;30;47m' # highlight
}

_config_no_change(){
  # $1 = _VAULT
  _TCPDUMP_CYCLE="60"
  _PATH_TO_VAULTS="$(pwd)/vaults/"
  _VAULT="${1}"
  _PATH_TO_VAULT="${_PATH_TO_VAULTS}${_VAULT}/"
  _PATH_TO_VAULT_LOGS="${_PATH_TO_VAULT}logs/"
  _PATH_TO_VAULT_PCAPS="${_PATH_TO_VAULT}pcaps/"
  _PATH_TO_VAULT_PCAPS_RAW="${_PATH_TO_VAULT_PCAPS}raw/"
  _PATH_TO_VAULT_PCAPS_INPUT="${_PATH_TO_VAULT_PCAPS}input/"
  _PATH_TO_VAULT_PCAPS_ARCHIVE="${_PATH_TO_VAULT_PCAPS}archive/"
  _PATH_TO_VAULT_PCAPS_EXPORT="${_PATH_TO_VAULT_PCAPS}export/"
  _VAULT_LOG_MAIN="${_PATH_TO_VAULT_LOGS}${_VAULT}_main.log"
  _VAULT_LOG_TCPDUMP="${_PATH_TO_VAULT_LOGS}${_VAULT}_tcpdump.log"
  _VAULT_PID_TCPDUMP_FILE="${_PATH_TO_VAULT}.${_VAULT}_tcpdump.PID"
  _VAULT_PID_PROCESSING_FILE="${_PATH_TO_VAULT}.${_VAULT}_processing.PID"
  if [ -f "${_VAULT_PID_TCPDUMP_FILE}" ] && [ $(pgrep -F "${_VAULT_PID_TCPDUMP_FILE}" 2> /dev/null ) ];
    then read _VAULT_PID_TCPDUMP < "${_VAULT_PID_TCPDUMP_FILE}";
    else _VAULT_PID_TCPDUMP=""; fi
  if [ -f "${_VAULT_PID_PROCESSING_FILE}" ] && [ $(pgrep -F "${_VAULT_PID_PROCESSING_FILE}" 2> /dev/null ) ];
    then read _VAULT_PID_PROCESSING < "${_VAULT_PID_PROCESSING_FILE}";
    else _VAULT_PID_PROCESSING=""; fi
}

_config(){
  local vault="default"
  if [ "${#1}" -gt 0 ]; then vault="${1}";  fi
  _config_no_change "${vault}"
  _config_maybe_change
  _config_yes_change
}

########################
### logging FUNCTIONS #
######################

_log(){
  # _log "log_level" "log_source" "${FUNCNAME[0]}" "log_context" "log_message";
  local log_level="${1}"
  local log_source="${2}"
  local log_function="${3}"
  local log_context="${4}"
  local log_message="${5}"
  local log_message="$(date +%FT%T%z),${log_level},${log_function},${log_context},${log_message}"
  local log_file="${_PCV_LOG_MAIN}"

  # override the default log_file if necessary
  case "${log_source}" in
    (vault) log_file="${_VAULT_LOG_MAIN}";;
    (*) ;;
  esac

  # verify logfile exists
  if [ ! -f "${log_file}" ];
  then
    # if not, run _build_structure
    _build_structure;
  # check log size, and archive if necessary
  elif [ $(wc -l < "${log_file}") -ge "${_LOG_MAX_LINES}" ]; then
    tail -n "${_LOG_MAX_LINES}" "${log_file}" > "${log_file}.old"
    rm -f "${log_file}"
    touch "${log_file}"
    # log the archive notice in the pcv_main logfile
    _log "warn" "pcv" "${FUNCNAME[0]}" "'_LOG_MAX_LINES'.met" "'${log_file##*/}'.archived,to.'${log_file##*/}.old'"
  fi

  case "${log_level}" in
    (halt)
      echo "${log_message}" | tee -a "${log_file}";
      exit 1;
      ;;
    (warn)
      if [ "${_VERBOSE_LEVEL}" -gt 0 ];
        then echo "${log_message}" | tee -a "${log_file}";
        else echo "${log_message}" >> "${log_file}"; fi
      ;;
    (status)
      if [ "${_VERBOSE_LEVEL}" -gt 1 ];
        then echo "${log_message}" | tee -a "${log_file}";
        else echo "${log_message}" >> "${log_file}"; fi
      ;;
    (info)
      if [ "${_VERBOSE_LEVEL}" -gt 2 ];
        then echo "${log_message}" | tee -a "${log_file}";
        else echo "${log_message}" >> "${log_file}"; fi
      ;;
    (*)
      echo "${log_message}" | tee -a "${log_file}";
      ;;
  esac
}


#####################
### tool FUNCTIONS #
###################

human_filesize() {
	awk -v sum="$1" ' BEGIN {hum[1024^3]="Gb"; hum[1024^2]="Mb"; hum[1024]="Kb"; for (x=1024^3; x>=1024; x/=1024) { if (sum>=x) { printf "%.2f %s\n",sum/x,hum[x]; break; } } if (sum<1024) print "1kb"; } '
}

_iso8601_dt(){
  # 2020-07-24T11:43:20-0500
  # YYYY-MM-DDTHH:MM:SS±TZNE
  case "${#1}" in
    (4) # YYYY
      if [[ "${1}" =~ ^[0-9]{4}$ ]];
        then echo $(date -d "${1}-01-01" "+%FT%T%z" 2> /dev/null);
      fi;;
    (7) # YYYY-MM
      if [[ "${1}" =~ ^[0-9]{4}-(0[1-9]|1[0-2])$ ]];
        then echo $(date -d "${1}-01" "+%FT%T%z" 2> /dev/null);
      fi;;
    (10) # YYYY-MM-DD
      if [[ "${1}" =~ ^[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[1-2][0-9]|3[0-1])$ ]];
        then echo $(date -d "${1}" "+%FT%T%z" 2> /dev/null);
      fi;;
    (13) # YYYY-MM-DDTHH
      if [[ "${1}" =~ ^[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[1-2][0-9]|3[0-1])T(0[0-9]|1[0-9]|2[0-3])$ ]];
        then echo $(date -d "${1}:00" "+%FT%T%z" 2> /dev/null);
      fi;;
    (16) # YYYY-MM-DDTHH:MM
      if [[ "${1}" =~ ^[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[1-2][0-9]|3[0-1])T(0[0-9]|1[0-9]|2[0-3]):([0-6][0-9])$ ]];
        then echo $(date -d "${1}" "+%FT%T%z" 2> /dev/null);
      fi;;
    (19) # YYYY-MM-DDTHH:MM:SS
      if [[ "${1}" =~ ^[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[1-2][0-9]|3[0-1])T(0[0-9]|1[0-9]|2[0-3]):([0-6][0-9]):([0-6][0-9])$ ]];
        then echo $(date -d "${1}" "+%FT%T%z" 2> /dev/null);
      fi;;
    (24) # YYYY-MM-DDTHH:MM:SS±TZNE
      if [[ "${1}" =~ ^[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[1-2][0-9]|3[0-1])T(0[0-9]|1[0-9]|2[0-3]):([0-6][0-9]):([0-6][0-9])(\-|\+)(0[0-9]|1[0-4])(00|15|30|45)$ ]];
        then echo $(date -d "${1}" "+%FT%T%z" 2> /dev/null);
      fi;;
    (*) ;; # do nothing if no match
  esac
}

_list_vaults(){
  local dirs=($(ls -d ${_PATH_TO_VAULTS}*/))
  local vault
  local usage
  local tcpdump_status
  local processing_status
  local tcpdump_status_color
  local processing_status_color
  
  dirs=( ${dirs[@]/$_PATH_TO_VAULTS} )
  dirs=( ${dirs[@]///} )

  printf " ${_C4}VAULT LIST${_C0}\n"
  printf " ${_C5}%*s${_C0} | ${_C5}%*s${_C0} | ${_C5}%*s${_C0} | ${_C5}%*s${_C0}\n" 26 "vault" 16 "tcpdump" 16 "processing" 10 "usage"

  for vault in "${dirs[@]}"; do
    _get_vault "${vault}"
    usage=$(du -sb ${_PATH_TO_VAULT} | cut -f1)
    usage=$(human_filesize ${usage})
    if [ ! -z "${_VAULT_PID_TCPDUMP}" ];
      then tcpdump_status_color="${_C2}"; tcpdump_status="${_VAULT_PID_TCPDUMP}";
      else tcpdump_status_color="${_C1}"; tcpdump_status="inactive"; fi
    if [ ! -z "${_VAULT_PID_PROCESSING}" ];
      then processing_status_color="${_C2}" processing_status="${_VAULT_PID_PROCESSING}";
      else processing_status_color="${_C1}"; processing_status="inactive"; fi

    printf " ${_C3}%*s${_C0} | ${tcpdump_status_color}%*s${_C0} | ${processing_status_color}%*s${_C0} | %*s\n" 26 "${vault}" 16 "${tcpdump_status}" 16 "${processing_status}" 10 "${usage}"
  done
}

_get_vault(){
  _config "${1}"
}

_is_vault(){
  local vault="${1}"
  if [[ "${vault}" =~ ^[a-zA-Z0-9]+$ ]] && [ $(ls "${_PATH_TO_VAULTS}" | grep "^${vault}$" | wc -l) -eq 1 ]; then
    echo "true"
  else
    echo ""
  fi
}

_is_interface(){
  if [ $(tcpdump --list-interfaces | grep "${1}" | wc -l) -eq 1 ]; then
    echo "true"
  else
    echo ""
  fi
}

_get_interface(){
  _TCPDUMP_INTERFACE="${1}"
}

_start(){
  _get_vault "${1}"
  if [ "${#2}" -gt 0 ]; then _get_interface "${2}"; fi
  _build_structure "silent"
  
  if [ -z "${_VAULT_PID_TCPDUMP}" ]; then
    printf " starting ${_C2}tcpdump${_C0} for ${_C2}${_VAULT}${_C0}\n";
    _start_tcpdump;
  else
    printf " ${_C3}tcpdump${_C0} already running for ${_C3}${_VAULT}${_C0}\n";
  fi

  if [ -z "${_VAULT_PID_PROCESSING}" ]; then
    printf " starting ${_C2}processing${_C0} for ${_C2}${_VAULT}${_C0}\n";
    _start_processing;
  else
    printf " ${_C3}processing${_C0} already running for ${_C3}${_VAULT}${_C0}\n";
  fi
}

_start_tcpdump(){
  _log "status" "vault" "${FUNCNAME[0]}" "starting.tcpdump" "'tcpdump -i ${_TCPDUMP_INTERFACE} -G ${_TCPDUMP_CYCLE} -w ${_PATH_TO_VAULT_PCAPS_RAW}%FT%T%z.pcap 1> /dev/null 2> ${_VAULT_LOG_TCPDUMP} &'"
  tcpdump -i "${_TCPDUMP_INTERFACE}" -G "${_TCPDUMP_CYCLE}" -w "${_PATH_TO_VAULT_PCAPS_RAW}%FT%T%z.pcap" 1> /dev/null 2> "${_VAULT_LOG_TCPDUMP}" &
  echo "$!" > "${_VAULT_PID_TCPDUMP_FILE}"
  _get_vault "${_VAULT}"
  if [ ! -z "${_VAULT_PID_TCPDUMP}" ]; then
    _log "status" "vault" "${FUNCNAME[0]}" "tcpdump.started" "'${_VAULT_PID_TCPDUMP}'"
    printf " ${_C2}tcpdump${_C0} started for ${_C3}${_VAULT}${_C0} on ${_C3}${_TCPDUMP_INTERFACE}${_C0} with PID '${_C3}${_VAULT_PID_TCPDUMP}${_C0}'\n";
  else
    printf " ${_C3}tcpdump${_C0} ${_C1}failed to start${_C0} for ${_C3}${_VAULT}${_C0} on ${_C3}${_TCPDUMP_INTERFACE}${_C0}\n";
    _log "halt" "vault" "${FUNCNAME[0]}" "tcpdump.failed" "'tcpdump failed to start'"
  fi
}

_start_processing(){
  _call_processing &> /dev/null &
  echo "$!" > "${_VAULT_PID_PROCESSING_FILE}"
  _get_vault "${_VAULT}"
  if [ ! -z "${_VAULT_PID_PROCESSING}" ]; then
    _log "status" "vault" "${FUNCNAME[0]}" "processing.started" "'${_VAULT_PID_PROCESSING}'"
    printf " ${_C2}processing${_C0} started for ${_C3}${_VAULT}${_C0} with PID '${_C3}${_VAULT_PID_PROCESSING}${_C0}'\n";
  else
    printf " ${_C3}processing${_C0} ${_C1}failed to start${_C0} for ${_C3}${_VAULT}${_C0}${_C0}\n";
    _log "halt" "vault" "${FUNCNAME[0]}" "processing.failed" "'processing failed to start'"
  fi
}

_stop(){
  _get_vault "${1}"
  _build_structure "silent"
  _stop_tcpdump;
  _stop_processing;
}

_stop_tcpdump(){
  _get_vault "${_VAULT}"
  if [ ! -z "${_VAULT_PID_TCPDUMP}" ]; then
    if $(kill -0 "${_VAULT_PID_TCPDUMP}" &> /dev/null); then
      $(kill "${_VAULT_PID_TCPDUMP}");
      echo "" > "${_VAULT_PID_TCPDUMP_FILE}"
      printf " ${_C2}killed${_C0} ${_C3}tcpdump${_C0} PDI ${_C3}${_VAULT_PID_TCPDUMP}${_C0} for ${_C3}${_VAULT}${_C0}\n";
      _log "status" "vault" "${FUNCNAME[0]}" "stopping.tcpdump" "'${_VAULT_PID_TCPDUMP}'"
    else
      # unable to kill process
      printf " ${_C1}kill failed${_C0} ${_C3}tcpdump${_C0} PDI ${_C3}${_VAULT_PID_TCPDUMP}${_C0} for ${_C3}${_VAULT}${_C0}\n";
      _log "halt" "vault" "${FUNCNAME[0]}" "kill.tcpdump.failed" "'${_VAULT_PID_TCPDUMP}'"
    fi
  else
    # process not running
      printf " ${_C1}no${_C0} tcpdump ${_C1}process running${_C0} for ${_C3}${_VAULT}${_C0}\n";
  fi
}

_stop_processing(){
  _get_vault "${_VAULT}"
  if [ ! -z "${_VAULT_PID_PROCESSING}" ]; then
    if $(kill -0 "${_VAULT_PID_PROCESSING}" &> /dev/null); then
      $(kill "${_VAULT_PID_PROCESSING}");
      echo "" > "${_VAULT_PID_PROCESSING_FILE}"
      printf " ${_C2}killed${_C0} ${_C3}processing${_C0} PDI ${_C3}${_VAULT_PID_PROCESSING}${_C0} for ${_C3}${_VAULT}${_C0}\n";
      _log "status" "vault" "${FUNCNAME[0]}" "stopping.processing" "'${_VAULT_PID_PROCESSING}'"
    else
      # unable to kill process
      printf " ${_C1}kill failed${_C0} ${_C3}processing${_C0} PDI ${_C3}${_VAULT_PID_PROCESSING}${_C0} for ${_C3}${_VAULT}${_C0}\n";
      _log "halt" "vault" "${FUNCNAME[0]}" "kill.processing.failed" "'${_VAULT_PID_PROCESSING}'"
    fi
  else
    # process not running
      printf " ${_C1}no${_C0} processing ${_C1}process running${_C0} for ${_C3}${_VAULT}${_C0}\n";
  fi
}

###########################
### processing FUNCTIONS #
#########################

_call_processing(){
  while true; do
    _processing
  	sleep "${_TCPDUMP_CYCLE}s"
  done
}

_processing(){
  local pcaps=()
  local pcap
  local update=()
  local skipped=()
  local datetime
  local year
  local month
  local day
  local hour
  local minute
  local nextdatetime
  local nextyear
  local nextmonth
  local nextday
  local nexthour
  local nextminute
  local relativedatetime
  local editcap_relativedatetime1
  local editcap_relativedatetime2
  local editcap_relativedatetime3
  local out1
  local out2
 
  # move completed pcaps from RAW to INPUT
  pcaps=($(ls "${_PATH_TO_VAULT_PCAPS_RAW}"))
  for pcap in "${pcaps[@]}"; do
    rawcheck=$(_iso8601_dt "${pcap/.pcap}")
    if [ "${#rawcheck}" -gt 0 ]; then
      if [ $(date -d "${pcap/.pcap}" "+%s") -lt $(date -d "- ${_TCPDUMP_CYCLE} seconds" "+%s") ]; then
        mv "${_PATH_TO_VAULT_PCAPS_RAW}${pcap}" "${_PATH_TO_VAULT_PCAPS_INPUT}${pcap}";
        update+=( "${pcap}" )
      else
        skipped+=( "${pcap}" )
      fi
    else
      # filename does not match the iso8601 pattern, skipping file
      skipped+=( "${pcap}" )
    fi
  done
  # log any moves
  if [ "${#update[@]}" -gt 0 ]; then _log "status" "vault" "${FUNCNAME[0]}" "RAW moved to INPUT" "'${update[*]}'"; fi
  # log any skipped files
  if [ "${#skipped[@]}" -gt 0 ]; then _log "warn" "vault" "${FUNCNAME[0]}" "RAW.skipped" "'${skipped[*]}'"; fi

  # process the INPUT pcaps and move data to ARCHIVE
  update=()
  skipped=()
  pcaps=($(ls "${_PATH_TO_VAULT_PCAPS_INPUT}"))
  for pcap in "${pcaps[@]}"; do
    relativedatetime=$(_iso8601_dt "${pcap/.pcap}")
    if [ "${#relativedatetime}" -gt 0 ]; then
      editcap_relativedatetime1=$(date -d "${relativedatetime}" "+%F %H:%M:00%z")
      editcap_relativedatetime2=$(date -d "${relativedatetime} + 1 minute" "+%F %H:%M:00%z")
      editcap_relativedatetime3=$(date -d "${relativedatetime} + 2 minute" "+%F %H:%M:00%z")
      datetime=$(date -u -d "${relativedatetime}" "+%FT%H:%M:00%z")
      year="${datetime:0:4}"
      month="${datetime:5:2}"
      day="${datetime:8:2}"
      hour="${datetime:11:2}"
      minute="${datetime:14:2}"
      nextdatetime=$(date -u -d "${datetime} + 1 minute" "+%FT%H:%M:00%z")
      nextyear="${nextdatetime:0:4}"
      nextmonth="${nextdatetime:5:2}"
      nextday="${nextdatetime:8:2}"
      nexthour="${nextdatetime:11:2}"
      nextminute="${nextdatetime:14:2}"
      if [ ! -d "${_PATH_TO_VAULT_PCAPS_ARCHIVE}${year}/${month}/${day}/${hour}/" ];
        then mkdir -p "${_PATH_TO_VAULT_PCAPS_ARCHIVE}${year}/${month}/${day}/${hour}/"; fi
      if [ ! -d "${_PATH_TO_VAULT_PCAPS_ARCHIVE}${nextyear}/${nextmonth}/${nextday}/${nexthour}/" ];
        then mkdir -p "${_PATH_TO_VAULT_PCAPS_ARCHIVE}${nextyear}/${nextmonth}/${nextday}/${nexthour}/"; fi

      out1="${_PATH_TO_VAULT_PCAPS_ARCHIVE}${year}/${month}/${day}/${hour}/${datetime}.pcap"
      if [ -f "${out1}.edit" ]; then rm -f "${out1}.edit"; fi
      out2="${_PATH_TO_VAULT_PCAPS_ARCHIVE}${nextyear}/${nextmonth}/${nextday}/${nexthour}/${nextdatetime}.pcap"
      if [ -f "${out2}.edit" ]; then rm -f "${out2}.edit"; fi

      editcap -A "${editcap_relativedatetime1}" -B "${editcap_relativedatetime2}" "${_PATH_TO_VAULT_PCAPS_INPUT}${pcap}" "${out1}.edit"
      editcap -A "${editcap_relativedatetime2}" -B "${editcap_relativedatetime3}" "${_PATH_TO_VAULT_PCAPS_INPUT}${pcap}" "${out2}.edit"

      # out1
      if [ -f "${out1}.gz" ]; then
        # merge the temp editcap export with the archive
        mergecap -F pcap -w "${out1}.merge" "${out1}.edit" "${out1}.gz"
        rm -f "${out1}.gz"
        rm -f "${out1}.edit"
        mv -f "${out1}.merge" "${out1}"
      else
        # move the temp editcap export to archive
        mv -f "${out1}.edit" "${out1}"
      fi

      # out2
      if [ -f "${out2}.gz" ]; then
        # merge the temp editcap export with the archive
        mergecap -F pcap -w "${out2}.merge" "${out2}.edit" "${out2}.gz"
        rm -f "${out2}.gz"
        rm -f "${out2}.edit"
        mv -f "${out2}.merge" "${out2}"
      else
        # move the temp editcap export to archive
        mv -f "${out2}.edit" "${out2}"
      fi

      gzip "${out1}"
      gzip "${out2}"

      rm -f "${_PATH_TO_VAULT_PCAPS_INPUT}${pcap}"
      update+=( "${pcap}" )
    else
      # filename does not match the iso8601 pattern, skipping file
      skipped+=( "${pcap}" )
    fi
  done
  # log any moves
  if [ "${#update[@]}" -gt 0 ]; then _log "status" "vault" "${FUNCNAME[0]}" "INPUT.processed" "'${update[*]}'"; fi
  # log any skipped files
  if [ "${#skipped[@]}" -gt 0 ]; then _log "status" "vault" "${FUNCNAME[0]}" "INPUT.skipped" "'${skipped[*]}'"; fi
}

##########################
### cleanup FUNCTIONS #
########################

_cleanup(){
  local from=$(date -u -d "${1}" "+%FT%H:%M:00%z");
  local to=$(date -u -d "${2}" "+%FT%H:%M:00%z");
  local from_epoc=$(date -u -d "${from}" +%s);
  local to_epoc=$(date -u -d "${to}" +%s);
  local time_span_in_seconds=$(( ${to_epoc} - ${from_epoc} ));
  local time_span_in_minutes=$(( ${time_span_in_seconds} / 60 ));
  local time_span_in_hours=$(( ${time_span_in_minutes} / 60 ));
  local time_span_in_days=$(( ${time_span_in_hours} / 24 ));
  local time_span_in_months_aprox=$(( ${time_span_in_days} / 31 ));
  local time_span_in_years_aprox=$(( ${time_span_in_days} / 365 ));
  time_span_in_months_aprox=$(( ${time_span_in_months_aprox} - ( 12 * ${time_span_in_years_aprox} ) ));
  time_span_in_days=$(( ${time_span_in_days} - ( 31 * ${time_span_in_months_aprox} ) - ( 365 * ${time_span_in_years_aprox} ) ));
  time_span_in_hours=$(( ${time_span_in_hours} - ( 24 * ${time_span_in_days} ) - ( 24 * 31 * ${time_span_in_months_aprox} ) - ( 24 * 365 * ${time_span_in_years_aprox} ) ));
  time_span_in_minutes=$(( ${time_span_in_minutes} - ( 60 * ${time_span_in_hours} ) - ( 60 * 24 * ${time_span_in_days} ) - ( 60 * 24 * 31 * ${time_span_in_months_aprox} ) - ( 60 * 24 * 365 * ${time_span_in_years_aprox} ) ));
  local path_to_this_pcap;
  local path_to_this_hour;
  local path_to_this_day;
  local path_to_this_month;
  local path_to_this_year;
  local pcaps=();
  local pcap;
  local pcap_epoc;
  local hours=();
  local hour;
  local hour_epoc_start;
  local hour_epoc_end;
  local days=();
  local day;
  local day_epoc_start;
  local day_epoc_end;
  local months=();
  local month;
  local month_epoc_start;
  local month_epoc_end;
  local years=();
  local year;
  local year_epoc_start;
  local year_epoc_end;

  if [ "${from:0:16}" = "${to:0:16}" ]; then
    # from[0000-00-00T00:00] = [0000-00-00T00:00]to
    # from & to match up to the same minute
    path_to_this_year="${_PATH_TO_VAULT_PCAPS_ARCHIVE}${from:0:4}/";
    path_to_this_month="${path_to_this_year}${from:5:2}/";
    path_to_this_day="${path_to_this_month}/${from:8:2}/";
    path_to_this_hour="${path_to_this_day}${from:11:2}/";
    path_to_this_pcap="${path_to_this_hour}/${from}.pcap.gz";
    echo "same minute";
    echo "from: ${from} = to: ${to}";
    if [ -f"${path_to_this_pcap}" ]; then
      rm -f "${path_to_this_pcap}";
      _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.progress" "rm -f ${path_to_this_pcap}";
      if [ -z "$(ls -A ${path_to_this_day})" ]; then
        # dir empty, del dir
        rm -rf "${path_to_this_day}";
        _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.empty.DIR" "rm -rf '${path_to_this_day}'";
        if [ -z "$(ls -A ${path_to_this_month})" ]; then
          # dir empty, del dir
          rm -rf "${path_to_this_month}";
          _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.empty.DIR" "rm -rf '${path_to_this_month}'";
          if [ -z "$(ls -A ${path_to_this_year})" ]; then
            # dir empty, del dir
            rm -rf "${path_to_this_year}";
            _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.empty.DIR" "rm -rf '${path_to_this_year}'";
          fi
        fi
      fi
    else
      _log "warn" "vault" "${FUNCNAME[0]}" "PCAP.NF" "! -f '${path_to_this_pcap}'";
    fi
  elif [ "${from:0:13}" = "${to:0:13}" ]; then
    # from[0000-00-00T00] = [0000-00-00T00]to
    # from & to match up to the same hour
    path_to_this_year="${_PATH_TO_VAULT_PCAPS_ARCHIVE}${from:0:4}/";
    path_to_this_month="${path_to_this_year}${from:5:2}/";
    path_to_this_day="${path_to_this_month}/${from:8:2}/";
    path_to_this_hour="${path_to_this_day}${from:11:2}/";
    if [ -d "${path_to_this_hour}" ]; then
      hour_epoc_start=$(date -u -d "${from:0:4}-${from:5:2}-${from:8:2}T${from:11:2}:00:00+0000" +%s);
        hour_epoc_end=$(date -u -d "${from:0:4}-${from:5:2}-${from:8:2}T${from:11:2}:00:00+0000 + 1 hour - 1 second" +%s);
      if [ ${hour_epoc_start} -ge ${from_epoc} ] && [ ${hour_epoc_end} -le ${to_epoc} ]; then
        # this hour is fully within the time range
        rm -rf "${path_to_this_hour}";
        _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.progress" "rm -rf '${path_to_this_hour}'";
        if [ -z "$(ls -A ${path_to_this_day})" ]; then
          # dir empty, del dir
          rm -rf "${path_to_this_day}";
          _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.empty.DIR" "rm -rf '${path_to_this_day}'";
          if [ -z "$(ls -A ${path_to_this_month})" ]; then
            # dir empty, del dir
            rm -rf "${path_to_this_month}";
            _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.empty.DIR" "rm -rf '${path_to_this_month}'";
            if [ -z "$(ls -A ${path_to_this_year})" ]; then
              # dir empty, del dir
              rm -rf "${path_to_this_year}";
              _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.empty.DIR" "rm -rf '${path_to_this_year}'";
            fi
          fi
        fi
      else
        # this hour is partially within the time range
        pcaps=($(ls "${path_to_this_hour}"))
        for pcap in ${pcaps[@]}; do
          pcap_epoc=$(date -u -d "${pcap/.pcap.gz}" +%s);
          if [ ${pcap_epoc} -ge ${from_epoc} ] && [ ${pcap_epoc} -le ${to_epoc} ]; then
            # this pcap is within the time range
            rm -f "${path_to_this_hour}${pcap}";
            _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.progress" "rm -f ${path_to_this_hour}${pcap}";
            if [ -z "$(ls -A ${path_to_this_hour})" ]; then
              # dir empty, del dir
              rm -rf "${path_to_this_day}";
              _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.empty.DIR" "rm -rf '${path_to_this_hour}'";
              if [ -z "$(ls -A ${path_to_this_day})" ]; then
                # dir empty, del dir
                rm -rf "${path_to_this_day}";
                _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.empty.DIR" "rm -rf '${path_to_this_day}'";
                if [ -z "$(ls -A ${path_to_this_month})" ]; then
                  # dir empty, del dir
                  rm -rf "${path_to_this_month}";
                  _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.empty.DIR" "rm -rf '${path_to_this_month}'";
                  if [ -z "$(ls -A ${path_to_this_year})" ]; then
                    # dir empty, del dir
                    rm -rf "${path_to_this_year}";
                    _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.empty.DIR" "rm -rf '${path_to_this_year}'";
                  fi
                fi
              fi
            fi
          elif [ ${pcap_epoc} -gt ${to_epoc} ]; then
            # this pcap is beyond the time range
            _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.completed" "time range endpoint met @ '${pcap}' exiting '${path_to_this_hour}'";
            # break 1 to exit the pcaps loop
            break 1;
          else
            _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.progress" "skipping pcap '${pcap}'";
          fi
        done
        _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.progress" "this hour scan complete '${path_to_this_hour}'";
      fi
      # if scan deleted all pcaps in dir, or if dir was already empty, del dir, if it still exists
      if [ -d "${path_to_this_hour}" ]; then
        if [ -z "$(ls -A ${path_to_this_hour})" ]; then
          rm -rf "${path_to_this_hour}";
          _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.empty.DIR" "rm -rf '${path_to_this_hour}'";
          if [ -z "$(ls -A ${path_to_this_day})" ]; then
            # dir empty, del dir
            rm -rf "${path_to_this_day}";
            _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.empty.DIR" "rm -rf '${path_to_this_day}'";
            if [ -z "$(ls -A ${path_to_this_month})" ]; then
              # dir empty, del dir
              rm -rf "${path_to_this_month}";
              _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.empty.DIR" "rm -rf '${path_to_this_month}'";
              if [ -z "$(ls -A ${path_to_this_year})" ]; then
                # dir empty, del dir
                rm -rf "${path_to_this_year}";
                _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.empty.DIR" "rm -rf '${path_to_this_year}'";
              fi
            fi
          fi
        fi
      fi
    else
      _log "warn" "vault" "${FUNCNAME[0]}" "DIR.NF" " ! -d '${path_to_this_hour}'";
      _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.completed" "scan complete '${path_to_this_hour}'";
    fi
  elif [ "${from:0:10}" = "${to:0:10}" ]; then
    # from[0000-00-00] = [0000-00-00]to
    # from & to match up to the same day
    path_to_this_year="${_PATH_TO_VAULT_PCAPS_ARCHIVE}${from:0:4}/";
    path_to_this_month="${path_to_this_year}${from:5:2}/";
    path_to_this_day="${path_to_this_month}/${from:8:2}/";
    if [ -d "${path_to_this_day}" ]; then
      day_epoc_start=$(date -u -d "${from:0:4}-${from:5:2}-${from:8:2}T00:00:00+0000" +%s);
        day_epoc_end=$(date -u -d "${from:0:4}-${from:5:2}-${from:8:2}T00:00:00+0000 + 1 day - 1 second" +%s);
      if [ ${day_epoc_start} -ge ${from_epoc} ] && [ ${day_epoc_end} -le ${to_epoc} ]; then
        # this day is fully within the time range
        rm -rf "${path_to_this_day}";
        _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.progress" "rm -rf '${path_to_this_day}'";
        if [ -z "$(ls -A ${path_to_this_month})" ]; then
          # dir empty, del dir
          rm -rf "${path_to_this_month}";
          _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.empty.DIR" "rm -rf '${path_to_this_month}'";
          if [ -z "$(ls -A ${path_to_this_year})" ]; then
            # dir empty, del dir
            rm -rf "${path_to_this_year}";
            _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.empty.DIR" "rm -rf '${path_to_this_year}'";
          fi
        fi
      else
        # this day is partially within the time range
        hours=($(ls "${path_to_this_day}"))
        for hour in ${hours[@]}; do
          path_to_this_hour="${path_to_this_day}${hour}/"
          if [ -z "$(ls -A ${path_to_this_hour})" ]; then
            # dir empty, del dir
            rm -rf "${path_to_this_hour}";
            _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.empty.DIR" "rm -rf '${path_to_this_hour}'";
            if [ -z "$(ls -A ${path_to_this_day})" ]; then
              # dir empty, del dir
              rm -rf "${path_to_this_day}";
              _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.empty.DIR" "rm -rf '${path_to_this_day}'";
              if [ -z "$(ls -A ${path_to_this_month})" ]; then
                # dir empty, del dir
                rm -rf "${path_to_this_month}";
                _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.empty.DIR" "rm -rf '${path_to_this_month}'";
                if [ -z "$(ls -A ${path_to_this_year})" ]; then
                  # dir empty, del dir
                  rm -rf "${path_to_this_year}";
                  _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.empty.DIR" "rm -rf '${path_to_this_year}'";
                fi
              fi
            fi
          else
            # dir not empty
            hour_epoc_start=$(date -u -d "${from:0:4}-${from:5:2}-${from:8:2}T${hour}:00:00+0000" +%s);
              hour_epoc_end=$(date -u -d "${from:0:4}-${from:5:2}-${from:8:2}T${hour}:00:00+0000 + 1 hour - 1 second" +%s);
            if [ ${hour_epoc_end} -lt ${from_epoc} ]; then
              # the end of this hour is before the time range
              _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.progress" "skipping hour '${path_to_this_hour}'";
            elif [ ${hour_epoc_start} -gt ${to_epoc} ]; then
              # the start of this hour is beyond the time range
              _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.completed" "time range endpoint met @ '${path_to_this_hour}' exiting '${path_to_this_day}'";
              # break 1 to exit the hours loop
              break 1;
            elif [ ${hour_epoc_start} -ge ${from_epoc} ] && [ ${hour_epoc_end} -le ${to_epoc} ]; then
              # this hour is fully within the time range
              rm -rf "${path_to_this_hour}";
              _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.progress" "rm -rf '${path_to_this_hour}'";
              if [ -z "$(ls -A ${path_to_this_day})" ]; then
                # dir empty, del dir
                rm -rf "${path_to_this_day}";
                _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.empty.DIR" "rm -rf '${path_to_this_day}'";
                if [ -z "$(ls -A ${path_to_this_month})" ]; then
                  # dir empty, del dir
                  rm -rf "${path_to_this_month}";
                  _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.empty.DIR" "rm -rf '${path_to_this_month}'";
                  if [ -z "$(ls -A ${path_to_this_year})" ]; then
                    # dir empty, del dir
                    rm -rf "${path_to_this_year}";
                    _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.empty.DIR" "rm -rf '${path_to_this_year}'";
                  fi
                fi
              fi
            else
              # this hour is partially within the time range
              pcaps=($(ls "${path_to_this_hour}"))
              for pcap in ${pcaps[@]}; do
                pcap_epoc=$(date -u -d "${pcap/.pcap.gz}" +%s);
                if [ ${pcap_epoc} -ge ${from_epoc} ] && [ ${pcap_epoc} -le ${to_epoc} ]; then
                  # this pcap is within the time range
                  rm -f "${path_to_this_hour}${pcap}";
                  _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.progress" "rm -f ${path_to_this_hour}${pcap}";
                  if [ -z "$(ls -A ${path_to_this_hour})" ]; then
                    # dir empty, del dir
                    rm -rf "${path_to_this_day}";
                    _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.empty.DIR" "rm -rf '${path_to_this_hour}'";
                    if [ -z "$(ls -A ${path_to_this_day})" ]; then
                      # dir empty, del dir
                      rm -rf "${path_to_this_day}";
                      _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.empty.DIR" "rm -rf '${path_to_this_day}'";
                      if [ -z "$(ls -A ${path_to_this_month})" ]; then
                        # dir empty, del dir
                        rm -rf "${path_to_this_month}";
                        _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.empty.DIR" "rm -rf '${path_to_this_month}'";
                        if [ -z "$(ls -A ${path_to_this_year})" ]; then
                          # dir empty, del dir
                          rm -rf "${path_to_this_year}";
                          _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.empty.DIR" "rm -rf '${path_to_this_year}'";
                        fi
                      fi
                    fi
                  fi
                elif [ ${pcap_epoc} -gt ${to_epoc} ]; then
                  # this pcap is beyond the time range
                  _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.completed" "time range endpoint met @ '${pcap}' exiting '${path_to_this_day}'";
                  # break 2 to exit the pcaps loop and the hours loop
                  break 2;
                else
                  _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.progress" "skipping pcap '${pcap}'";
                fi
              done
              _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.progress" "scan complete '${path_to_this_hour}'";
            fi
          fi
        done
        _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.progress" "scan complete '${path_to_this_day}'";
      fi
      # if scan deleted all pcaps in dir, or if dir was already empty, del dir, if it still exists
      if [ -d "${path_to_this_day}" ]; then
        if [ -z "$(ls -A ${path_to_this_day})" ]; then
          rm -rf "${path_to_this_day}";
          _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.empty.DIR" "rm -rf '${path_to_this_day}'";
          if [ -z "$(ls -A ${path_to_this_month})" ]; then
            # dir empty, del dir
            rm -rf "${path_to_this_month}";
            _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.empty.DIR" "rm -rf '${path_to_this_month}'";
            if [ -z "$(ls -A ${path_to_this_year})" ]; then
              # dir empty, del dir
              rm -rf "${path_to_this_year}";
              _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.empty.DIR" "rm -rf '${path_to_this_year}'";
            fi
          fi
        fi
      fi
    else
      _log "warn" "vault" "${FUNCNAME[0]}" "DIR.NF" " ! -d '${path_to_this_day}'";
      _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.completed" "scan complete '${path_to_this_day}'";
    fi
  elif [ "${from:0:7}" = "${to:0:7}" ]; then
    # from[0000-00] = [0000-00]to
    # from & to match up to the same month
    path_to_this_year="${_PATH_TO_VAULT_PCAPS_ARCHIVE}${from:0:4}/";
    path_to_this_month="${path_to_this_year}${from:5:2}/";
    if [ -d "${path_to_this_month}" ]; then
      month_epoc_start=$(date -u -d "${from:0:4}-${from:5:2}-01T00:00:00+0000" +%s);
        month_epoc_end=$(date -u -d "${from:0:4}-${from:5:2}-01T00:00:00+0000 + 1 month - 1 second" +%s);
      if [ ${month_epoc_start} -ge ${from_epoc} ] && [ ${month_epoc_end} -le ${to_epoc} ]; then
        # this month is fully within the time range
        rm -rf "${path_to_this_month}";
        _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.progress" "rm -rf '${path_to_this_month}'";
        if [ -z "$(ls -A ${path_to_this_year})" ]; then
          # dir empty, del dir
          rm -rf "${path_to_this_year}";
          _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.empty.DIR" "rm -rf '${path_to_this_year}'";
        fi
      else
        # this month is partially within the time range
        days=($(ls "${path_to_this_month}"))
        for day in ${days[@]}; do
          path_to_this_day="${path_to_this_month}${day}/"
          if [ -z "$(ls -A ${path_to_this_day})" ]; then
            # dir empty, del dir
            rm -rf "${path_to_this_day}";
            _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.empty.DIR" "rm -rf '${path_to_this_day}'";
            if [ -z "$(ls -A ${path_to_this_month})" ]; then
              # dir empty, del dir
              rm -rf "${path_to_this_month}";
              _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.empty.DIR" "rm -rf '${path_to_this_month}'";
              if [ -z "$(ls -A ${path_to_this_year})" ]; then
                # dir empty, del dir
                rm -rf "${path_to_this_year}";
                _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.empty.DIR" "rm -rf '${path_to_this_year}'";
              fi
            fi
          else
            # dir not empty
            day_epoc_start=$(date -u -d "${from:0:4}-${from:5:2}-${day}T00:00:00+0000" +%s);
              day_epoc_end=$(date -u -d "${from:0:4}-${from:5:2}-${day}T00:00:00+0000 + 1 day - 1 second" +%s);
            if [ ${day_epoc_end} -lt ${from_epoc} ]; then
              # the end of this day is before the time range
              _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.empty.DIR" "skipping day '${path_to_this_day}'";
            elif [ ${day_epoc_start} -gt ${to_epoc} ]; then
              # the start of this day is beyond the time range
              _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.completed" "time range endpoint met @ '${path_to_this_day}' exiting '${path_to_this_month}'";
              # break 1 to exit the days loop
              break 1;
            elif [ ${day_epoc_start} -ge ${from_epoc} ] && [ ${day_epoc_end} -le ${to_epoc} ]; then
              # this day is fully within the time range
              rm -rf "${path_to_this_day}";
              _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.progress" "rm -rf '${path_to_this_day}'";
            else
              # this day is partially within the time range
              hours=($(ls "${path_to_this_day}"))
              for hour in ${hours[@]}; do
                path_to_this_hour="${path_to_this_day}${hour}/"
                if [ -z "$(ls -A ${path_to_this_hour})" ]; then
                  # dir empty, del dir
                  rm -rf "${path_to_this_hour}";
                  _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.empty.DIR" "rm -rf '${path_to_this_hour}'";
                  if [ -z "$(ls -A ${path_to_this_day})" ]; then
                    # dir empty, del dir
                    rm -rf "${path_to_this_day}";
                    _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.empty.DIR" "rm -rf '${path_to_this_day}'";
                    if [ -z "$(ls -A ${path_to_this_month})" ]; then
                      # dir empty, del dir
                      rm -rf "${path_to_this_month}";
                      _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.empty.DIR" "rm -rf '${path_to_this_month}'";
                      if [ -z "$(ls -A ${path_to_this_year})" ]; then
                        # dir empty, del dir
                        rm -rf "${path_to_this_year}";
                        _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.empty.DIR" "rm -rf '${path_to_this_year}'";
                      fi
                    fi
                  fi
                else
                  # dir not empty
                  hour_epoc_start=$(date -u -d "${from:0:4}-${from:5:2}-${day}T${hour}:00:00+0000" +%s);
                    hour_epoc_end=$(date -u -d "${from:0:4}-${from:5:2}-${day}T${hour}:00:00+0000 + 1 hour - 1 second" +%s);
                  if [ ${hour_epoc_end} -lt ${from_epoc} ]; then
                    # the end of this hour is before the time range
                    _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.progress" "skipping hour '${path_to_this_hour}'";
                  elif [ ${hour_epoc_start} -gt ${to_epoc} ]; then
                    # the start of this hour is beyond the time range
                    _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.completed" "time range endpoint met @ '${path_to_this_hour}' exiting '${path_to_this_day}'";
                    # break 2 to exit the hour loop and day loop
                    break 2;
                  elif [ ${hour_epoc_start} -ge ${from_epoc} ] && [ ${hour_epoc_end} -le ${to_epoc} ]; then
                    # this hour is fully within the time range
                    rm -rf "${path_to_this_hour}";
                    _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.progress" "rm -rf '${path_to_this_hour}'";
                    if [ -z "$(ls -A ${path_to_this_day})" ]; then
                      # dir empty, del dir
                      rm -rf "${path_to_this_day}";
                      _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.empty.DIR" "rm -rf '${path_to_this_day}'";
                      if [ -z "$(ls -A ${path_to_this_month})" ]; then
                        # dir empty, del dir
                        rm -rf "${path_to_this_month}";
                        _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.empty.DIR" "rm -rf '${path_to_this_month}'";
                        if [ -z "$(ls -A ${path_to_this_year})" ]; then
                          # dir empty, del dir
                          rm -rf "${path_to_this_year}";
                          _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.empty.DIR" "rm -rf '${path_to_this_year}'";
                        fi
                      fi
                    fi
                  else
                    # this hour is partially within the time range
                    pcaps=($(ls "${path_to_this_hour}"))
                    for pcap in ${pcaps[@]}; do
                      pcap_epoc=$(date -u -d "${pcap/.pcap.gz}" +%s);
                      if [ ${pcap_epoc} -ge ${from_epoc} ] && [ ${pcap_epoc} -le ${to_epoc} ]; then
                        # this pcap is within the time range
                        rm -f "${path_to_this_hour}${pcap}";
                        _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.progress" "rm -f ${path_to_this_hour}${pcap}";
                        if [ -z "$(ls -A ${path_to_this_hour})" ]; then
                          # dir empty, del dir
                          rm -rf "${path_to_this_day}";
                          _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.empty.DIR" "rm -rf '${path_to_this_hour}'";
                          if [ -z "$(ls -A ${path_to_this_day})" ]; then
                            # dir empty, del dir
                            rm -rf "${path_to_this_day}";
                            _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.empty.DIR" "rm -rf '${path_to_this_day}'";
                            if [ -z "$(ls -A ${path_to_this_month})" ]; then
                              # dir empty, del dir
                              rm -rf "${path_to_this_month}";
                              _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.empty.DIR" "rm -rf '${path_to_this_month}'";
                              if [ -z "$(ls -A ${path_to_this_year})" ]; then
                                # dir empty, del dir
                                rm -rf "${path_to_this_year}";
                                _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.empty.DIR" "rm -rf '${path_to_this_year}'";
                              fi
                            fi
                          fi
                        fi
                      elif [ ${pcap_epoc} -gt ${to_epoc} ]; then
                        # this pcap is beyond the time range
                        _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.completed" "time range endpoint met @ '${pcap}' exiting '${path_to_this_day}'";
                        # break 3 to exit the pcaps loop and hours loop and day loop
                        break 3;
                      else
                        _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.progress" "skipping pcap '${pcap}'";
                      fi
                    done
                    _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.progress" "scan complete '${path_to_this_hour}'";
                  fi
                fi
              done
              _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.progress" "scan complete '${path_to_this_day}'";
            fi
          fi
        done
        _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.progress" "scan complete '${path_to_this_month}'";
      fi
      # if scan deleted all pcaps in dir, or if dir was already empty, del dir, if it still exists
      if [ -d "${path_to_this_month}" ]; then
        if [ -z "$(ls -A ${path_to_this_month})" ]; then
          rm -rf "${path_to_this_month}";
          _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.empty.DIR" "rm -rf '${path_to_this_month}'";
          if [ -z "$(ls -A ${path_to_this_year})" ]; then
            # dir empty, del dir
            rm -rf "${path_to_this_year}";
            _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.empty.DIR" "rm -rf '${path_to_this_year}'";
          fi
        fi
      fi
    else
      _log "warn" "vault" "${FUNCNAME[0]}" "DIR.NF" " ! -d '${path_to_this_month}'";
      _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.completed" "scan complete '${path_to_this_month}'";
    fi
  elif [ "${from:0:4}" = "${to:0:4}" ]; then
    # from[0000] = [0000]to
    # from & to match up to the same year
    path_to_this_year="${_PATH_TO_VAULT_PCAPS_ARCHIVE}${from:0:4}/";
    if [ -d "${path_to_this_year}" ]; then
      year_epoc_start=$(date -u -d "${from:0:4}-01-01T00:00:00+0000" +%s);
        year_epoc_end=$(date -u -d "${from:0:4}-01-01T00:00:00+0000 + 1 year - 1 second" +%s);
      if [ ${year_epoc_start} -ge ${from_epoc} ] && [ ${year_epoc_end} -le ${to_epoc} ]; then
        # this year is fully within the time range
        rm -rf "${path_to_this_year}";
        _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.progress" "rm -rf '${path_to_this_year}'";
      else
        # this year is partially within the time range
        months=($(ls "${path_to_this_year}"))
        for month in ${months[@]}; do
          path_to_this_month="${path_to_this_year}${month}/"
          if [ -z "$(ls -A ${path_to_this_month})" ]; then
            # dir empty, del dir
            rm -rf "${path_to_this_month}";
            _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.empty.DIR" "rm -rf '${path_to_this_month}'";
            if [ -z "$(ls -A ${path_to_this_year})" ]; then
              # dir empty, del dir
              rm -rf "${path_to_this_year}";
              _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.empty.DIR" "rm -rf '${path_to_this_year}'";
            fi
          else
            # dir not empty
            month_epoc_start=$(date -u -d "${from:0:4}-${month}-01T00:00:00+0000" +%s);
              month_epoc_end=$(date -u -d "${from:0:4}-${month}-01T00:00:00+0000 + 1 month - 1 second" +%s);
            if [ ${month_epoc_end} -lt ${from_epoc} ]; then
              # the end of this month is before the time range
              _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.progress" "skipping month '${path_to_this_month}'";
            elif [ ${month_epoc_start} -gt ${to_epoc} ]; then
              # the start of this month is beyond the time range
              _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.completed" "time range endpoint met @ '${path_to_this_month}' exiting '${path_to_this_year}'";
              # break 1 to exit the months loop
              break 1;
            elif [ ${month_epoc_start} -ge ${from_epoc} ] && [ ${month_epoc_end} -le ${to_epoc} ]; then
              # this month is fully within the time range
              rm -rf "${path_to_this_month}";
              _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.progress" "rm -rf '${path_to_this_month}'";
              if [ -z "$(ls -A ${path_to_this_year})" ]; then
                # dir empty, del dir
                rm -rf "${path_to_this_year}";
                _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.empty.DIR" "rm -rf '${path_to_this_year}'";
              fi
            else
              # this month is partially within the time range
              days=($(ls "${path_to_this_month}"))
              for day in ${days[@]}; do
                path_to_this_day="${path_to_this_month}${day}/"
                if [ -z "$(ls -A ${path_to_this_day})" ]; then
                  # dir empty, del dir
                  rm -rf "${path_to_this_day}";
                  _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.empty.DIR" "rm -rf '${path_to_this_day}'";
                  if [ -z "$(ls -A ${path_to_this_month})" ]; then
                    # dir empty, del dir
                    rm -rf "${path_to_this_month}";
                    _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.empty.DIR" "rm -rf '${path_to_this_month}'";
                    if [ -z "$(ls -A ${path_to_this_year})" ]; then
                      # dir empty, del dir
                      rm -rf "${path_to_this_year}";
                      _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.empty.DIR" "rm -rf '${path_to_this_year}'";
                    fi
                  fi
                else
                  # dir not empty
                  day_epoc_start=$(date -u -d "${from:0:4}-${month}-${day}T00:00:00+0000" +%s);
                    day_epoc_end=$(date -u -d "${from:0:4}-${month}-${day}T00:00:00+0000 + 1 day - 1 second" +%s);
                  if [ ${day_epoc_end} -lt ${from_epoc} ]; then
                    # the end of this day is before the time range
                    _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.progress" "skipping day '${path_to_this_day}'";
                  elif [ ${day_epoc_start} -gt ${to_epoc} ]; then
                    # the start of this day is beyond the time range
                    _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.completed" "time range endpoint met @ '${path_to_this_day}' exiting '${path_to_this_month}'";
                    # break 2 to exit the days loop and month loop
                    break 2;
                  elif [ ${day_epoc_start} -ge ${from_epoc} ] && [ ${day_epoc_end} -le ${to_epoc} ]; then
                    # this day is fully within the time range
                    rm -rf "${path_to_this_day}";
                    _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.progress" "rm -rf '${path_to_this_day}'";
                    if [ -z "$(ls -A ${path_to_this_month})" ]; then
                      # dir empty, del dir
                      rm -rf "${path_to_this_month}";
                      _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.empty.DIR" "rm -rf '${path_to_this_month}'";
                      if [ -z "$(ls -A ${path_to_this_year})" ]; then
                        # dir empty, del dir
                        rm -rf "${path_to_this_year}";
                        _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.empty.DIR" "rm -rf '${path_to_this_year}'";
                      fi
                    fi
                  else
                    # this day is partially within the time range
                    hours=($(ls "${path_to_this_day}"))
                    for hour in ${hours[@]}; do
                      path_to_this_hour="${path_to_this_day}${hour}/"
                      if [ -z "$(ls -A ${path_to_this_hour})" ]; then
                        # dir empty, del dir
                        rm -rf "${path_to_this_hour}";
                        _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.empty.DIR" "rm -rf '${path_to_this_hour}'";
                        if [ -z "$(ls -A ${path_to_this_day})" ]; then
                          # dir empty, del dir
                          rm -rf "${path_to_this_day}";
                          _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.empty.DIR" "rm -rf '${path_to_this_day}'";
                          if [ -z "$(ls -A ${path_to_this_month})" ]; then
                            # dir empty, del dir
                            rm -rf "${path_to_this_month}";
                            _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.empty.DIR" "rm -rf '${path_to_this_month}'";
                            if [ -z "$(ls -A ${path_to_this_year})" ]; then
                              # dir empty, del dir
                              rm -rf "${path_to_this_year}";
                              _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.empty.DIR" "rm -rf '${path_to_this_year}'";
                            fi
                          fi
                        fi
                      else
                        # dir not empty
                        hour_epoc_start=$(date -u -d "${from:0:4}-${month}-${day}T${hour}:00:00+0000" +%s);
                          hour_epoc_end=$(date -u -d "${from:0:4}-${month}-${day}T${hour}:00:00+0000 + 1 hour - 1 second" +%s);
                        if [ ${hour_epoc_end} -lt ${from_epoc} ]; then
                          # the end of this hour is before the time range
                          _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.progress" "skipping hour '${path_to_this_hour}'";
                        elif [ ${hour_epoc_start} -gt ${to_epoc} ]; then
                          # the start of this hour is beyond the time range
                          _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.completed" "time range endpoint met @ '${path_to_this_hour}' exiting '${path_to_this_day}'";
                          # break 3 to exit the hours loop and days loop and month loop
                          break 3;
                        elif [ ${hour_epoc_start} -ge ${from_epoc} ] && [ ${hour_epoc_end} -le ${to_epoc} ]; then
                          # this hour is fully within the time range
                          rm -rf "${path_to_this_hour}";
                          _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.progress" "rm -rf '${path_to_this_hour}'";
                          if [ -z "$(ls -A ${path_to_this_day})" ]; then
                            # dir empty, del dir
                            rm -rf "${path_to_this_day}";
                            _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.empty.DIR" "rm -rf '${path_to_this_day}'";
                            if [ -z "$(ls -A ${path_to_this_month})" ]; then
                              # dir empty, del dir
                              rm -rf "${path_to_this_month}";
                              _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.empty.DIR" "rm -rf '${path_to_this_month}'";
                              if [ -z "$(ls -A ${path_to_this_year})" ]; then
                                # dir empty, del dir
                                rm -rf "${path_to_this_year}";
                                _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.empty.DIR" "rm -rf '${path_to_this_year}'";
                              fi
                            fi
                          fi
                        else
                          # this hour is partially within the time range
                          pcaps=($(ls "${path_to_this_hour}"))
                          for pcap in ${pcaps[@]}; do
                            pcap_epoc=$(date -u -d "${pcap/.pcap.gz}" +%s);
                            if [ ${pcap_epoc} -ge ${from_epoc} ] && [ ${pcap_epoc} -le ${to_epoc} ]; then
                              # this pcap is within the time range
                              rm -f "${path_to_this_hour}${pcap}";
                              _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.progress" "rm -f ${path_to_this_hour}${pcap}";
                              if [ -z "$(ls -A ${path_to_this_hour})" ]; then
                                # dir empty, del dir
                                rm -rf "${path_to_this_day}";
                                _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.empty.DIR" "rm -rf '${path_to_this_hour}'";
                                if [ -z "$(ls -A ${path_to_this_day})" ]; then
                                  # dir empty, del dir
                                  rm -rf "${path_to_this_day}";
                                  _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.empty.DIR" "rm -rf '${path_to_this_day}'";
                                  if [ -z "$(ls -A ${path_to_this_month})" ]; then
                                    # dir empty, del dir
                                    rm -rf "${path_to_this_month}";
                                    _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.empty.DIR" "rm -rf '${path_to_this_month}'";
                                    if [ -z "$(ls -A ${path_to_this_year})" ]; then
                                      # dir empty, del dir
                                      rm -rf "${path_to_this_year}";
                                      _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.empty.DIR" "rm -rf '${path_to_this_year}'";
                                    fi
                                  fi
                                fi
                              fi
                            elif [ ${pcap_epoc} -gt ${to_epoc} ]; then
                              # this pcap is beyond the time range
                              _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.completed" "time range endpoint met @ '${pcap}' exiting '${path_to_this_day}'";
                              # break 4 to exit the pcaps loop and hours loop and days loop and months loop
                              break 4;
                            else
                              _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.progress" "skipping pcap '${pcap}'";
                            fi
                          done
                          _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.progress" "this hour scan complete '${path_to_this_hour}'";
                        fi
                      fi
                    done
                    _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.progress" "this day scan complete '${path_to_this_day}'";
                  fi
                fi
              done
              _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.progress" "this month scan complete '${path_to_this_month}'";
            fi
          fi
        done
        _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.progress" "this year scan complete '${path_to_this_year}'";
      fi
      # if scan deleted all pcaps in dir, or if dir was already empty, del dir, if it still exists
      if [ -d "${path_to_this_year}" ]; then
        if [ -z "$(ls -A ${path_to_this_year})" ]; then
          rm -rf "${path_to_this_year}";
          _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.empty.DIR" "rm -rf '${path_to_this_year}'";
        fi
      fi
    else
      _log "warn" "vault" "${FUNCNAME[0]}" "DIR.NF" " ! -d '${path_to_this_year}'";
      _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.completed" "this year scan complete '${path_to_this_year}'";
    fi
  else
    # from != to
    # from & to DO NOT match up
    if [ -d "${_PATH_TO_VAULT_PCAPS_ARCHIVE}" ]; then
      years=($(ls "${_PATH_TO_VAULT_PCAPS_ARCHIVE}"));
      for year in ${years[@]}; do
        path_to_this_year="${_PATH_TO_VAULT_PCAPS_ARCHIVE}${year}/";
        if [ -z "$(ls -A ${path_to_this_year})" ]; then
          # dir empty, del dir
          rm -rf "${path_to_this_year}";
          _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.empty.DIR" "rm -rf '${path_to_this_year}'";
        else
          # dir not empty
          year_epoc_start=$(date -u -d "${year}-01-01T00:00:00+0000" +%s);
            year_epoc_end=$(date -u -d "${year}-01-01T00:00:00+0000 + 1 year - 1 second" +%s);
          if [ ${year_epoc_end} -lt ${from_epoc} ]; then
            # the end of this year is before the time range
            _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.progress" "skipping year '${path_to_this_year}'";
          elif [ ${year_epoc_start} -gt ${to_epoc} ]; then
            # the start of this year is beyond the time range
            _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.completed" "time range endpoint met @ '${path_to_this_year}' exiting '${_PATH_TO_VAULT_PCAPS_ARCHIVE}'";
            # break 1 to exit the years loop
            break 1;
          elif [ ${year_epoc_start} -ge ${from_epoc} ] && [ ${year_epoc_end} -le ${to_epoc} ]; then
            # this year is fully within the time range
            rm -rf "${path_to_this_year}";
            _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.empty.DIR" "rm -rf '${path_to_this_year}'";
          else
            # this year is partially within the time range
            months=($(ls "${path_to_this_year}"))
            for month in ${months[@]}; do
              path_to_this_month="${path_to_this_year}${month}/"
              if [ -z "$(ls -A ${path_to_this_month})" ]; then
                # dir empty, del dir
                rm -rf "${path_to_this_month}";
                _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.empty.DIR" "rm -rf '${path_to_this_month}'";
                if [ -z "$(ls -A ${path_to_this_year})" ]; then
                  # dir empty, del dir
                  rm -rf "${path_to_this_year}";
                  _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.empty.DIR" "rm -rf '${path_to_this_year}'";
                fi
              else
                # dir not empty
                month_epoc_start=$(date -u -d "${year}-${month}-01T00:00:00+0000" +%s);
                  month_epoc_end=$(date -u -d "${year}-${month}-01T00:00:00+0000 + 1 month - 1 second" +%s);
                if [ ${month_epoc_end} -lt ${from_epoc} ]; then
                  # the end of this month is before the time range
                  _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.progress" "skipping month '${path_to_this_month}'";
                elif [ ${month_epoc_start} -gt ${to_epoc} ]; then
                  # the start of this month is beyond the time range
                  _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.completed" "time range endpoint met @ '${path_to_this_month}' exiting '${path_to_this_year}'";
                  # break 2 to exit the months loop and years loop
                  break 2;
                elif [ ${month_epoc_start} -ge ${from_epoc} ] && [ ${month_epoc_end} -le ${to_epoc} ]; then
                  # this month is fully within the time range
                  rm -rf "${path_to_this_month}";
                  _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.empty.DIR" "rm -rf '${path_to_this_month}'";
                  if [ -z "$(ls -A ${path_to_this_year})" ]; then
                    # dir empty, del dir
                    rm -rf "${path_to_this_year}";
                    _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.empty.DIR" "rm -rf '${path_to_this_year}'";
                  fi
                else
                  # this month is partially within the time range
                  days=($(ls "${path_to_this_month}"))
                  for day in ${days[@]}; do
                    path_to_this_day="${path_to_this_month}${day}/"
                    if [ -z "$(ls -A ${path_to_this_day})" ]; then
                      # dir empty, del dir
                      rm -rf "${path_to_this_day}";
                      _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.empty.DIR" "rm -rf '${path_to_this_day}'";
                      if [ -z "$(ls -A ${path_to_this_month})" ]; then
                        # dir empty, del dir
                        rm -rf "${path_to_this_month}";
                        _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.empty.DIR" "rm -rf '${path_to_this_month}'";
                        if [ -z "$(ls -A ${path_to_this_year})" ]; then
                          # dir empty, del dir
                          rm -rf "${path_to_this_year}";
                          _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.empty.DIR" "rm -rf '${path_to_this_year}'";
                        fi
                      fi
                    else
                      # dir not empty
                      day_epoc_start=$(date -u -d "${year}-${month}-${day}T00:00:00+0000" +%s);
                        day_epoc_end=$(date -u -d "${year}-${month}-${day}T00:00:00+0000 + 1 day - 1 second" +%s);
                      if [ ${day_epoc_end} -lt ${from_epoc} ]; then
                        # the end of this day is before the time range
                        _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.progress" "skipping day '${path_to_this_day}'";
                      elif [ ${day_epoc_start} -gt ${to_epoc} ]; then
                        # the start of this day is beyond the time range
                        _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.completed" "time range endpoint met @ '${path_to_this_day}'  exiting '${path_to_this_month}'";
                        # break 3 to exit the days loop and month loop and years loop
                        break 3;
                      elif [ ${day_epoc_start} -ge ${from_epoc} ] && [ ${day_epoc_end} -le ${to_epoc} ]; then
                        # this day is fully within the time range
                        rm -rf "${path_to_this_day}";
                        _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.empty.DIR" "rm -rf '${path_to_this_day}'";
                        if [ -z "$(ls -A ${path_to_this_month})" ]; then
                          # dir empty, del dir
                          rm -rf "${path_to_this_month}";
                          _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.empty.DIR" "rm -rf '${path_to_this_month}'";
                          if [ -z "$(ls -A ${path_to_this_year})" ]; then
                            # dir empty, del dir
                            rm -rf "${path_to_this_year}";
                            _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.empty.DIR" "rm -rf '${path_to_this_year}'";
                          fi
                        fi
                      else
                        # this day is partially within the time range
                        hours=($(ls "${path_to_this_day}"))
                        for hour in ${hours[@]}; do
                          path_to_this_hour="${path_to_this_day}${hour}/"
                          if [ -z "$(ls -A ${path_to_this_hour})" ]; then
                            # dir empty, del dir
                            rm -rf "${path_to_this_hour}";
                            _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.empty.DIR" "rm -rf '${path_to_this_hour}'";
                            if [ -z "$(ls -A ${path_to_this_day})" ]; then
                              # dir empty, del dir
                              rm -rf "${path_to_this_day}";
                              _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.empty.DIR" "rm -rf '${path_to_this_day}'";
                              if [ -z "$(ls -A ${path_to_this_month})" ]; then
                                # dir empty, del dir
                                rm -rf "${path_to_this_month}";
                                _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.empty.DIR" "rm -rf '${path_to_this_month}'";
                                if [ -z "$(ls -A ${path_to_this_year})" ]; then
                                  # dir empty, del dir
                                  rm -rf "${path_to_this_year}";
                                  _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.empty.DIR" "rm -rf '${path_to_this_year}'";
                                fi
                              fi
                            fi
                          else
                            # dir not empty
                            hour_epoc_start=$(date -u -d "${year}-${month}-${day}T${hour}:00:00+0000" +%s);
                              hour_epoc_end=$(date -u -d "${year}-${month}-${day}T${hour}:00:00+0000 + 1 hour - 1 second" +%s);
                            if [ ${hour_epoc_end} -lt ${from_epoc} ]; then
                              # the end of this hour is before the time range
                              _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.empty.DIR" "skipping hour '${path_to_this_hour}'";
                            elif [ ${hour_epoc_start} -gt ${to_epoc} ]; then
                              # the start of this hour is beyond the time range
                              _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.completed" "time range endpoint met @ '${path_to_this_hour}' exiting '${path_to_this_day}'";
                              # break 4 to exit the hours loop and days loop and month loop and years loop
                              break 4;
                            elif [ ${hour_epoc_start} -ge ${from_epoc} ] && [ ${hour_epoc_end} -le ${to_epoc} ]; then
                              # this hour is fully within the time range
                              rm -rf "${path_to_this_hour}";
                              _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.empty.DIR" "rm -rf '${path_to_this_hour}'";
                              if [ -z "$(ls -A ${path_to_this_day})" ]; then
                                # dir empty, del dir
                                rm -rf "${path_to_this_day}";
                                _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.empty.DIR" "rm -rf '${path_to_this_day}'";
                                if [ -z "$(ls -A ${path_to_this_month})" ]; then
                                  # dir empty, del dir
                                  rm -rf "${path_to_this_month}";
                                  _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.empty.DIR" "rm -rf '${path_to_this_month}'";
                                  if [ -z "$(ls -A ${path_to_this_year})" ]; then
                                    # dir empty, del dir
                                    rm -rf "${path_to_this_year}";
                                    _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.empty.DIR" "rm -rf '${path_to_this_year}'";
                                  fi
                                fi
                              fi
                            else
                              # this hour is partially within the time range
                              pcaps=($(ls "${path_to_this_hour}"))
                              for pcap in ${pcaps[@]}; do
                                pcap_epoc=$(date -u -d "${pcap/.pcap.gz}" +%s);
                                if [ ${pcap_epoc} -ge ${from_epoc} ] && [ ${pcap_epoc} -le ${to_epoc} ]; then
                                  # this pcap is within the time range
                                  rm -f "${path_to_this_hour}${pcap}";
                                  _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.progress" "rm -f ${path_to_this_hour}${pcap}";                                  
                                  if [ -z "$(ls -A ${path_to_this_hour})" ]; then
                                    # dir empty, del dir
                                    rm -rf "${path_to_this_day}";
                                    _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.empty.DIR" "rm -rf '${path_to_this_hour}'";
                                    if [ -z "$(ls -A ${path_to_this_day})" ]; then
                                      # dir empty, del dir
                                      rm -rf "${path_to_this_day}";
                                      _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.empty.DIR" "rm -rf '${path_to_this_day}'";
                                      if [ -z "$(ls -A ${path_to_this_month})" ]; then
                                        # dir empty, del dir
                                        rm -rf "${path_to_this_month}";
                                        _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.empty.DIR" "rm -rf '${path_to_this_month}'";
                                        if [ -z "$(ls -A ${path_to_this_year})" ]; then
                                          # dir empty, del dir
                                          rm -rf "${path_to_this_year}";
                                          _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.empty.DIR" "rm -rf '${path_to_this_year}'";
                                        fi
                                      fi
                                    fi
                                  fi
                                elif [ ${pcap_epoc} -gt ${to_epoc} ]; then
                                  # this pcap is beyond the time range
                                  _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.completed" "time range endpoint met @ '${pcap}', exiting '${path_to_this_day}'";
                                  # break 5 to exit the pcaps loop and hours loop and days loop and months loop and years loop
                                  break 5;
                                else
                                  _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.progress" "skipping pcap '${pcap}'";
                                fi
                              done
                              _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.progress" "scan complete '${path_to_this_hour}'";
                            fi
                          fi
                        done
                        _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.progress" "scan complete '${path_to_this_day}'";
                      fi
                    fi
                  done
                  _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.progress" "scan complete '${path_to_this_month}'";
                fi
              fi
            done
            _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.progress" "scan complete '${path_to_this_year}'";
          fi
        fi
      done
      _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.completed" "all years scanned in '${_PATH_TO_VAULT_PCAPS_ARCHIVE}'";
    else
      _log "warn" "vault" "${FUNCNAME[0]}" "DIR.NF" "! -d '${_PATH_TO_VAULT_PCAPS_ARCHIVE}'";
      _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.completed" "all years scanned in '${_PATH_TO_VAULT_PCAPS_ARCHIVE}'";
    fi
  fi

  printf " ${_C4}CLEANUP COMPLETED${_C0}\n";
  printf " cleanup range: ${_C3}%24s${_C0} <=> ${_C3}%24s${_C0}\n" ${from} ${to};
  printf " ${_C3}%d${_C0} years | ${_C3}%d${_C0} months | ${_C3}%d${_C0} days | ${_C3}%d${_C0} hours | ${_C3}%d${_C0} minutes\n" ${time_span_in_years_aprox} ${time_span_in_months_aprox} ${time_span_in_days} ${time_span_in_hours} ${time_span_in_minutes};
}

#######################
### export FUNCTIONS #
#####################

_export(){
  local from=$(date -u -d "${1}" "+%FT%H:%M:00%z");
  local to=$(date -u -d "${2}" "+%FT%H:%M:00%z");
  local from_epoc=$(date -u -d "${from}" +%s);
  local to_epoc=$(date -u -d "${to}" +%s);
  local ex_from=$(date -u -d "${from}" "+%F");
  local ex_to=$(date -u -d "${to}" "+%F");
  local path_to_this_export="${_PATH_TO_VAULT_PCAPS_EXPORT}${ex_from}_to_${ex_to}/";
  if [ -d "${path_to_this_export}" ]; then path_to_this_export="${_PATH_TO_VAULT_PCAPS_EXPORT}${ex_from}_to_${ex_to}_$(date -u '+%s')/"; fi
  mkdir -p "${path_to_this_export}";
  local time_span_in_seconds=$(( ${to_epoc} - ${from_epoc} ));
  local time_span_in_minutes=$(( ${time_span_in_seconds} / 60 ));
  local time_span_in_hours=$(( ${time_span_in_minutes} / 60 ));
  local time_span_in_days=$(( ${time_span_in_hours} / 24 ));
  local time_span_in_months_aprox=$(( ${time_span_in_days} / 31 ));
  local time_span_in_years_aprox=$(( ${time_span_in_days} / 365 ));
  if [ ${time_span_in_years_aprox} -lt 0 ]; then time_span_in_years_aprox=0; fi
  time_span_in_months_aprox=$(( ${time_span_in_months_aprox} - ( 12 * ${time_span_in_years_aprox} ) ));
  if [ ${time_span_in_months_aprox} -lt 0 ]; then time_span_in_months_aprox=0; fi
  time_span_in_days=$(( ${time_span_in_days} - ( 31 * ${time_span_in_months_aprox} ) - ( 365 * ${time_span_in_years_aprox} ) ));
  if [ ${time_span_in_days} -lt 0 ]; then time_span_in_days=0; fi
  time_span_in_hours=$(( ${time_span_in_hours} - ( 24 * ${time_span_in_days} ) - ( 24 * 31 * ${time_span_in_months_aprox} ) - ( 24 * 365 * ${time_span_in_years_aprox} ) ));
  if [ ${time_span_in_hours} -lt 0 ]; then time_span_in_hours=0; fi
  time_span_in_minutes=$(( ${time_span_in_minutes} - ( 60 * ${time_span_in_hours} ) - ( 60 * 24 * ${time_span_in_days} ) - ( 60 * 24 * 31 * ${time_span_in_months_aprox} ) - ( 60 * 24 * 365 * ${time_span_in_years_aprox} ) ));
  if [ ${time_span_in_minutes} -lt 0 ]; then time_span_in_minutes=0; fi
  local path_to_this_pcap;
  local path_to_this_hour;
  local path_to_this_day;
  local path_to_this_month;
  local path_to_this_year;
  local pcaps=();
  local pcap;
  local pcap_epoc;
  local hours=();
  local hour;
  local hour_epoc_start;
  local hour_epoc_end;
  local days=();
  local day;
  local day_epoc_start;
  local day_epoc_end;
  local months=();
  local month;
  local month_epoc_start;
  local month_epoc_end;
  local years=();
  local year;
  local year_epoc_start;
  local year_epoc_end;
  local this_merge_limit="${3}";
  this_merge_limit=$(( ${this_merge_limit} ));
  this_merge_limit=$(( ${this_merge_limit} * 1024 * 1024 ));
  local summary_flag;
  case "${4}" in
    (summary-only) summary_flag="${4}";;
    (no-summary) summary_flag="${4}";;
    (*) summary_flag="default";;
  esac
  local pcaps_to_export=();
  local merge_buffer=();
  local merge_buffer_size=0;
  local summary_count=0;
  local merge_buffer_temp_name="";

  echo "";
  echo "scanning pcaps for export...";

  if [ "${from:0:16}" = "${to:0:16}" ]; then
    # from[0000-00-00T00:00] = [0000-00-00T00:00]to
    # from & to match up to the same minute
    path_to_this_year="${_PATH_TO_VAULT_PCAPS_ARCHIVE}${from:0:4}/";
    path_to_this_month="${path_to_this_year}${from:5:2}/";
    path_to_this_day="${path_to_this_month}/${from:8:2}/";
    path_to_this_hour="${path_to_this_day}${from:11:2}/";
    path_to_this_pcap="${path_to_this_hour}/${from}.pcap.gz";
    if [ -f"${path_to_this_pcap}" ]; then
      pcaps_to_export+=( "${path_to_this_pcap}" );
      _log "status" "vault" "${FUNCNAME[0]}" "EXPORT.progress" "cp ${path_to_this_pcap} ${path_to_this_export}${from}.pcap.gz";
    else
      _log "warn" "vault" "${FUNCNAME[0]}" "FILE.NF" "! -f '${path_to_this_pcap}'";
    fi
  elif [ "${from:0:13}" = "${to:0:13}" ]; then
    # from[0000-00-00T00] = [0000-00-00T00]to
    # from & to match up to the same hour
    path_to_this_year="${_PATH_TO_VAULT_PCAPS_ARCHIVE}${from:0:4}/";
    path_to_this_month="${path_to_this_year}${from:5:2}/";
    path_to_this_day="${path_to_this_month}/${from:8:2}/";
    path_to_this_hour="${path_to_this_day}${from:11:2}/";
    if [ -d "${path_to_this_hour}" ]; then
      hour_epoc_start=$(date -u -d "${from:0:4}-${from:5:2}-${from:8:2}T${from:11:2}:00:00+0000" +%s);
        hour_epoc_end=$(date -u -d "${from:0:4}-${from:5:2}-${from:8:2}T${from:11:2}:00:00+0000 + 1 hour - 1 second" +%s);
      # this hour is partially or fully within the time range
      pcaps=($(ls "${path_to_this_hour}"));
      for pcap in ${pcaps[@]}; do
        pcap_epoc=$(date -u -d "${pcap/.pcap.gz}" +%s);
        if [ ${pcap_epoc} -ge ${from_epoc} ] && [ ${pcap_epoc} -le ${to_epoc} ]; then
          # this pcap is within the time range
          pcaps_to_export+=( "${path_to_this_hour}${pcap}" );
          _log "status" "vault" "${FUNCNAME[0]}" "EXPORT.progress" "cp '${path_to_this_hour}${pcap}' '${path_to_this_export}${pcap}'";
        elif [ ${pcap_epoc} -gt ${to_epoc} ]; then
          # this pcap is beyond the time range
          _log "status" "vault" "${FUNCNAME[0]}" "EXPORT.progress" "time range endpoint met @ '${pcap}' exiting '${path_to_this_hour}'";
          # break 1 to exit the pcaps loop
          break 1;
        else
          _log "status" "vault" "${FUNCNAME[0]}" "EXPORT.progress" "skipping pcap '${pcap}'";
        fi
      done
      _log "status" "vault" "${FUNCNAME[0]}" "EXPORT.progress" "scan complete '${path_to_this_hour}'";
    else
      _log "warn" "vault" "${FUNCNAME[0]}" "DIR.NF" " ! -d '${path_to_this_hour}'";
      _log "status" "vault" "${FUNCNAME[0]}" "EXPORT.progress" "scan complete '${path_to_this_hour}'";
    fi
  elif [ "${from:0:10}" = "${to:0:10}" ]; then
    # from[0000-00-00] = [0000-00-00]to
    # from & to match up to the same day
    path_to_this_year="${_PATH_TO_VAULT_PCAPS_ARCHIVE}${from:0:4}/";
    path_to_this_month="${path_to_this_year}${from:5:2}/";
    path_to_this_day="${path_to_this_month}/${from:8:2}/";
    if [ -d "${path_to_this_day}" ]; then
      day_epoc_start=$(date -u -d "${from:0:4}-${from:5:2}-${from:8:2}T00:00:00+0000" +%s);
        day_epoc_end=$(date -u -d "${from:0:4}-${from:5:2}-${from:8:2}T00:00:00+0000 + 1 day - 1 second" +%s);
      # this hour is partially or fully within the time range
      hours=($(ls "${path_to_this_day}"));
      for hour in ${hours[@]}; do
        path_to_this_hour="${path_to_this_day}${hour}/";
        hour_epoc_start=$(date -u -d "${from:0:4}-${from:5:2}-${from:8:2}T${hour}:00:00+0000" +%s);
          hour_epoc_end=$(date -u -d "${from:0:4}-${from:5:2}-${from:8:2}T${hour}:00:00+0000 + 1 hour - 1 second" +%s);
        if [ ${hour_epoc_end} -lt ${from_epoc} ]; then
          # the end of this hour is before the time range
          _log "status" "vault" "${FUNCNAME[0]}" "EXPORT.progress" "skipping hour '${path_to_this_hour}'";
        elif [ ${hour_epoc_start} -gt ${to_epoc} ]; then
          # the start of this hour is beyond the time range
          _log "status" "vault" "${FUNCNAME[0]}" "EXPORT.progress" "time range endpoint met @ '${path_to_this_hour}' exiting '${path_to_this_day}'";
          # break 1 to exit the hours loop
          break 1;
        else
          # this hour is partially or fully within the time range
          pcaps=($(ls "${path_to_this_hour}"));
          for pcap in ${pcaps[@]}; do
            pcap_epoc=$(date -u -d "${pcap/.pcap.gz}" +%s);
            if [ ${pcap_epoc} -ge ${from_epoc} ] && [ ${pcap_epoc} -le ${to_epoc} ]; then
              # this pcap is within the time range
              pcaps_to_export+=( "${path_to_this_hour}${pcap}" );
              _log "status" "vault" "${FUNCNAME[0]}" "EXPORT.progress" "cp '${path_to_this_hour}${pcap}' '${path_to_this_export}${pcap}'";
            elif [ ${pcap_epoc} -gt ${to_epoc} ]; then
              # this pcap is beyond the time range
              _log "status" "vault" "${FUNCNAME[0]}" "EXPORT.progress" "time range endpoint met @ '${pcap}' exiting '${path_to_this_day}'";
              # break 2 to exit the pcaps loop and the hours loop
              break 2;
            else
              _log "status" "vault" "${FUNCNAME[0]}" "EXPORT.progress" "skipping pcap '${pcap}'";
            fi
          done
          _log "status" "vault" "${FUNCNAME[0]}" "EXPORT.progress" "scan complete '${path_to_this_hour}'";
        fi
      done
      _log "status" "vault" "${FUNCNAME[0]}" "EXPORT.progress" "scan complete '${path_to_this_day}'";
    else
      _log "warn" "vault" "${FUNCNAME[0]}" "DIR.NF" " ! -d '${path_to_this_day}'";
      _log "status" "vault" "${FUNCNAME[0]}" "EXPORT.progress" "scan complete '${path_to_this_day}'";
    fi
  elif [ "${from:0:7}" = "${to:0:7}" ]; then
    # from[0000-00] = [0000-00]to
    # from & to match up to the same month
    path_to_this_year="${_PATH_TO_VAULT_PCAPS_ARCHIVE}${from:0:4}/";
    path_to_this_month="${path_to_this_year}${from:5:2}/";
    if [ -d "${path_to_this_month}" ]; then
      month_epoc_start=$(date -u -d "${from:0:4}-${from:5:2}-01T00:00:00+0000" +%s);
        month_epoc_end=$(date -u -d "${from:0:4}-${from:5:2}-01T00:00:00+0000 + 1 month - 1 second" +%s);
        # this month is fully or partially within the time range
      days=($(ls "${path_to_this_month}"));
      for day in ${days[@]}; do
        path_to_this_day="${path_to_this_month}${day}/";
        day_epoc_start=$(date -u -d "${from:0:4}-${from:5:2}-${day}T00:00:00+0000" +%s);
          day_epoc_end=$(date -u -d "${from:0:4}-${from:5:2}-${day}T00:00:00+0000 + 1 day - 1 second" +%s);
        if [ ${day_epoc_end} -lt ${from_epoc} ]; then
          # the end of this day is before the time range
          _log "status" "vault" "${FUNCNAME[0]}" "EXPORT.progress" "skipping day '${path_to_this_day}'";
        elif [ ${day_epoc_start} -gt ${to_epoc} ]; then
          # the start of this day is beyond the time range
          _log "status" "vault" "${FUNCNAME[0]}" "EXPORT.progress" "time range endpoint met @ '${path_to_this_day}' exiting '${path_to_this_month}'";
          # break 1 to exit the days loop
          break 1;
        else
          # this day is fully or partially within the time range
          hours=($(ls "${path_to_this_day}"));
          for hour in ${hours[@]}; do
            path_to_this_hour="${path_to_this_day}${hour}/";
            # dir not empty
            hour_epoc_start=$(date -u -d "${from:0:4}-${from:5:2}-${day}T${hour}:00:00+0000" +%s);
              hour_epoc_end=$(date -u -d "${from:0:4}-${from:5:2}-${day}T${hour}:00:00+0000 + 1 hour - 1 second" +%s);
            if [ ${hour_epoc_end} -lt ${from_epoc} ]; then
              # the end of this hour is before the time range
              _log "status" "vault" "${FUNCNAME[0]}" "EXPORT.progress" "skipping hour '${path_to_this_hour}'";
            elif [ ${hour_epoc_start} -gt ${to_epoc} ]; then
              # the start of this hour is beyond the time range
              _log "status" "vault" "${FUNCNAME[0]}" "EXPORT.progress" "time range endpoint met @ '${path_to_this_hour}' exiting '${path_to_this_day}'";
              # break 2 to exit the hour loop and day loop
              break 2;
            else
              # this hour is fully or partially within the time range
              pcaps=($(ls "${path_to_this_hour}"));
              for pcap in ${pcaps[@]}; do
                pcap_epoc=$(date -u -d "${pcap/.pcap.gz}" +%s);
                if [ ${pcap_epoc} -ge ${from_epoc} ] && [ ${pcap_epoc} -le ${to_epoc} ]; then
                  # this pcap is within the time range
                  pcaps_to_export+=( "${path_to_this_hour}${pcap}" );
                  _log "status" "vault" "${FUNCNAME[0]}" "EXPORT.progress" "cp '${path_to_this_hour}${pcap}' '${path_to_this_export}${pcap}'";
                elif [ ${pcap_epoc} -gt ${to_epoc} ]; then
                  # this pcap is beyond the time range
                  _log "status" "vault" "${FUNCNAME[0]}" "EXPORT.progress" "time range endpoint met @ '${pcap}' exiting '${path_to_this_day}'";
                  # break 3 to exit the pcaps loop and hours loop and day loop
                  break 3;
                else
                  _log "status" "vault" "${FUNCNAME[0]}" "EXPORT.progress" "skipping pcap '${pcap}'";
                fi
              done
              _log "status" "vault" "${FUNCNAME[0]}" "EXPORT.progress" "scan complete '${path_to_this_hour}'";
            fi
          done
          _log "status" "vault" "${FUNCNAME[0]}" "EXPORT.progress" "scan complete '${path_to_this_day}'";
        fi
      done
      _log "status" "vault" "${FUNCNAME[0]}" "EXPORT.progress" "scan complete '${path_to_this_month}'";
    else
      _log "warn" "vault" "${FUNCNAME[0]}" "DIR.NF" " ! -d '${path_to_this_month}'";
      _log "status" "vault" "${FUNCNAME[0]}" "EXPORT.progress" "scan complete '${path_to_this_month}'";
    fi
  elif [ "${from:0:4}" = "${to:0:4}" ]; then
    # from[0000] = [0000]to
    # from & to match up to the same year
    path_to_this_year="${_PATH_TO_VAULT_PCAPS_ARCHIVE}${from:0:4}/";
    if [ -d "${path_to_this_year}" ]; then
      year_epoc_start=$(date -u -d "${from:0:4}-01-01T00:00:00+0000" +%s);
        year_epoc_end=$(date -u -d "${from:0:4}-01-01T00:00:00+0000 + 1 year - 1 second" +%s);
      # this year is fully or partially within the time range
      months=($(ls "${path_to_this_year}"));
      for month in ${months[@]}; do
        path_to_this_month="${path_to_this_year}${month}/";
        month_epoc_start=$(date -u -d "${from:0:4}-${month}-01T00:00:00+0000" +%s);
          month_epoc_end=$(date -u -d "${from:0:4}-${month}-01T00:00:00+0000 + 1 month - 1 second" +%s);
        if [ ${month_epoc_end} -lt ${from_epoc} ]; then
          # the end of this month is before the time range
          _log "status" "vault" "${FUNCNAME[0]}" "EXPORT.progress" "skipping month '${path_to_this_month}'";
        elif [ ${month_epoc_start} -gt ${to_epoc} ]; then
          # the start of this month is beyond the time range
          _log "status" "vault" "${FUNCNAME[0]}" "EXPORT.progress" "time range endpoint met @ ${path_to_this_month} exiting '${path_to_this_year}'";
          # break 1 to exit the months loop
          break 1;
        else
          # this month is fully or partially within the time range
          days=($(ls "${path_to_this_month}"));
          for day in ${days[@]}; do
            path_to_this_day="${path_to_this_month}${day}/";
            day_epoc_start=$(date -u -d "${from:0:4}-${month}-${day}T00:00:00+0000" +%s);
              day_epoc_end=$(date -u -d "${from:0:4}-${month}-${day}T00:00:00+0000 + 1 day - 1 second" +%s);
            if [ ${day_epoc_end} -lt ${from_epoc} ]; then
              # the end of this day is before the time range
              _log "status" "vault" "${FUNCNAME[0]}" "EXPORT.progress" "skipping day '${path_to_this_day}'";
            elif [ ${day_epoc_start} -gt ${to_epoc} ]; then
              # the start of this day is beyond the time range
              _log "status" "vault" "${FUNCNAME[0]}" "EXPORT.progress" "time range endpoint met @ ${path_to_this_day} exiting '${path_to_this_month}'";
              # break 2 to exit the days loop and month loop
              break 2;
            else
              # this day is fully or partially within the time range
              hours=($(ls "${path_to_this_day}"));
              for hour in ${hours[@]}; do
                path_to_this_hour="${path_to_this_day}${hour}/";
                # dir not empty
                hour_epoc_start=$(date -u -d "${from:0:4}-${month}-${day}T${hour}:00:00+0000" +%s);
                  hour_epoc_end=$(date -u -d "${from:0:4}-${month}-${day}T${hour}:00:00+0000 + 1 hour - 1 second" +%s);
                if [ ${hour_epoc_end} -lt ${from_epoc} ]; then
                  # the end of this hour is before the time range
                  _log "status" "vault" "${FUNCNAME[0]}" "EXPORT.progress" "skipping hour '${path_to_this_hour}'";
                elif [ ${hour_epoc_start} -gt ${to_epoc} ]; then
                  # the start of this hour is beyond the time range
                  _log "status" "vault" "${FUNCNAME[0]}" "EXPORT.progress" "time range endpoint met @ '${path_to_this_hour}' exiting '${path_to_this_day}'";
                  # break 3 to exit the hours loop and days loop and month loop
                  break 3;
                else
                  # this hour is fully or partially within the time range
                  pcaps=($(ls "${path_to_this_hour}"));
                  for pcap in ${pcaps[@]}; do
                    pcap_epoc=$(date -u -d "${pcap/.pcap.gz}" +%s);
                    if [ ${pcap_epoc} -ge ${from_epoc} ] && [ ${pcap_epoc} -le ${to_epoc} ]; then
                      # this pcap is within the time range
                      pcaps_to_export+=( "${path_to_this_hour}${pcap}" );
                      _log "status" "vault" "${FUNCNAME[0]}" "EXPORT.progress" "cp '${path_to_this_hour}${pcap}' '${path_to_this_export}${pcap}'";
                    elif [ ${pcap_epoc} -gt ${to_epoc} ]; then
                      # this pcap is beyond the time range
                      _log "status" "vault" "${FUNCNAME[0]}" "EXPORT.progress" "time range endpoint met @ ${pcap} exiting '${path_to_this_day}'";
                      # break 4 to exit the pcaps loop and hours loop and days loop and months loop
                      break 4;
                    else
                      _log "status" "vault" "${FUNCNAME[0]}" "EXPORT.progress" "skipping pcap '${pcap}'";
                    fi
                  done
                  _log "status" "vault" "${FUNCNAME[0]}" "EXPORT.progress" "scan complete '${path_to_this_hour}'";
                fi
              done
              _log "status" "vault" "${FUNCNAME[0]}" "EXPORT.progress" "scan complete '${path_to_this_day}'";
            fi
          done
          _log "status" "vault" "${FUNCNAME[0]}" "EXPORT.progress" "scan complete '${path_to_this_month}'";
        fi
      done
      _log "status" "vault" "${FUNCNAME[0]}" "EXPORT.progress" "scan complete '${path_to_this_year}'";
    else
      _log "warn" "vault" "${FUNCNAME[0]}" "DIR.NF" " ! -d '${path_to_this_year}'";
      _log "status" "vault" "${FUNCNAME[0]}" "EXPORT.progress" "scan complete '${path_to_this_year}'";
    fi
  else
    # from != to
    # from & to DO NOT match up
    if [ -d "${_PATH_TO_VAULT_PCAPS_ARCHIVE}" ]; then
      years=($(ls "${_PATH_TO_VAULT_PCAPS_ARCHIVE}"));
      for year in ${years[@]}; do
        path_to_this_year="${_PATH_TO_VAULT_PCAPS_ARCHIVE}${year}/";
        year_epoc_start=$(date -u -d "${year}-01-01T00:00:00+0000" +%s);
          year_epoc_end=$(date -u -d "${year}-01-01T00:00:00+0000 + 1 year - 1 second" +%s);
        if [ ${year_epoc_end} -lt ${from_epoc} ]; then
          # the end of this year is before the time range
          _log "status" "vault" "${FUNCNAME[0]}" "EXPORT.progress" "skipping year '${path_to_this_year}'";
        elif [ ${year_epoc_start} -gt ${to_epoc} ]; then
          # the start of this year is beyond the time range
          _log "status" "vault" "${FUNCNAME[0]}" "EXPORT.progress" "time range endpoint met @ '${path_to_this_year}' exiting '${_PATH_TO_VAULT_PCAPS_ARCHIVE}'";
          # break 1 to exit the years loop
          break 1;
        else
          # this year is fully or partially within the time range
          months=($(ls "${path_to_this_year}"));
          for month in ${months[@]}; do
            path_to_this_month="${path_to_this_year}${month}/";
            month_epoc_start=$(date -u -d "${year}-${month}-01T00:00:00+0000" +%s);
              month_epoc_end=$(date -u -d "${year}-${month}-01T00:00:00+0000 + 1 month - 1 second" +%s);
            if [ ${month_epoc_end} -lt ${from_epoc} ]; then
              # the end of this month is before the time range
              _log "status" "vault" "${FUNCNAME[0]}" "EXPORT.progress" "skipping month '${path_to_this_month}'";
            elif [ ${month_epoc_start} -gt ${to_epoc} ]; then
              # the start of this month is beyond the time range
              _log "status" "vault" "${FUNCNAME[0]}" "EXPORT.progress" "time range endpoint met @ '${path_to_this_month}' exiting '${path_to_this_year}'";
              # break 2 to exit the months loop and years loop
              break 2;
            else
              # this month is fully or partially within the time range
              days=($(ls "${path_to_this_month}"));
              for day in ${days[@]}; do
                path_to_this_day="${path_to_this_month}${day}/";
                day_epoc_start=$(date -u -d "${year}-${month}-${day}T00:00:00+0000" +%s);
                  day_epoc_end=$(date -u -d "${year}-${month}-${day}T00:00:00+0000 + 1 day - 1 second" +%s);
                if [ ${day_epoc_end} -lt ${from_epoc} ]; then
                  # the end of this day is before the time range
                  _log "status" "vault" "${FUNCNAME[0]}" "EXPORT.progress" "skipping day '${path_to_this_day}'";
                elif [ ${day_epoc_start} -gt ${to_epoc} ]; then
                  # the start of this day is beyond the time range
                  _log "status" "vault" "${FUNCNAME[0]}" "EXPORT.progress" "time range endpoint met @ '${path_to_this_day}' exiting '${path_to_this_month}'";
                  # break 3 to exit the days loop and month loop and years loop
                  break 3;
                else
                  # this day is fully or partially within the time range
                  hours=($(ls "${path_to_this_day}"));
                  for hour in ${hours[@]}; do
                  path_to_this_hour="${path_to_this_day}${hour}/"
                    hour_epoc_start=$(date -u -d "${year}-${month}-${day}T${hour}:00:00+0000" +%s);
                      hour_epoc_end=$(date -u -d "${year}-${month}-${day}T${hour}:00:00+0000 + 1 hour - 1 second" +%s);
                    if [ ${hour_epoc_end} -lt ${from_epoc} ]; then
                      # the end of this hour is before the time range
                      _log "status" "vault" "${FUNCNAME[0]}" "EXPORT.progress" "skipping hour '${path_to_this_hour}'";
                    elif [ ${hour_epoc_start} -gt ${to_epoc} ]; then
                      # the start of this hour is beyond the time range
                      _log "status" "vault" "${FUNCNAME[0]}" "EXPORT.progress" "time range endpoint met @ '${path_to_this_hour}' exiting '${path_to_this_day}'";
                      # break 4 to exit the hours loop and days loop and month loop and years loop
                      break 4;
                    else
                      # this hour is fully or partially within the time range
                      pcaps=($(ls "${path_to_this_hour}"));
                      for pcap in ${pcaps[@]}; do
                        pcap_epoc=$(date -u -d "${pcap/.pcap.gz}" +%s);
                        if [ ${pcap_epoc} -ge ${from_epoc} ] && [ ${pcap_epoc} -le ${to_epoc} ]; then
                          # this pcap is within the time range
                          pcaps_to_export+=( "${path_to_this_hour}${pcap}" );
                          _log "status" "vault" "${FUNCNAME[0]}" "EXPORT.progress" "cp '${path_to_this_hour}${pcap}' '${path_to_this_export}${pcap}'";                                
                        elif [ ${pcap_epoc} -gt ${to_epoc} ]; then
                          # this pcap is beyond the time range
                          _log "status" "vault" "${FUNCNAME[0]}" "EXPORT.progress" "time range endpoint met @ '${pcap}' exiting '${path_to_this_day}'";
                          # break 5 to exit the pcaps loop and hours loop and days loop and months loop and years loop
                          break 5;
                        else
                          _log "status" "vault" "${FUNCNAME[0]}" "EXPORT.progress" "skipping pcap '${pcap}'";
                        fi
                      done
                      _log "status" "vault" "${FUNCNAME[0]}" "EXPORT.progress" "scan complete '${path_to_this_hour}'";
                    fi
                  done
                  _log "status" "vault" "${FUNCNAME[0]}" "EXPORT.progress" "scan complete '${path_to_this_day}'";
                fi
              done
              _log "status" "vault" "${FUNCNAME[0]}" "EXPORT.progress" "scan complete '${path_to_this_month}'";
            fi
          done
          _log "status" "vault" "${FUNCNAME[0]}" "EXPORT.progress" "scan complete '${path_to_this_year}'";
        fi
      done
      _log "status" "vault" "${FUNCNAME[0]}" "EXPORT.progress" "scan complete '${_PATH_TO_VAULT_PCAPS_ARCHIVE}'";
    else
      _log "warn" "vault" "${FUNCNAME[0]}" "DIR.NF" " ! -d '${_PATH_TO_VAULT_PCAPS_ARCHIVE}'";
      _log "status" "vault" "${FUNCNAME[0]}" "EXPORT.progress" "scan complete '${_PATH_TO_VAULT_PCAPS_ARCHIVE}'";
    fi
  fi

  echo "export scan completed...";
  
  case "${summary_flag}" in
    (default) echo "exporting & summarizing...";;
    (no-summary) echo "exporting only...";;
    (summary-only) echo "summarizing only...";;
    (*) _log "warn" "vault" "${FUNCNAME[0]}" "unknown argument" "summary_flag '${summary_flag}'";;
  esac
  
  echo "";
  
  merge_buffer=();
  merge_buffer_size=0;
  merge_buffer_temp_pcaps=();
  summary_count=0;
  merge_buffer_temp_name="";
  if [ ${#pcaps_to_export[@]} -gt 0 ]; then
    for pcap in ${pcaps_to_export[@]}; do
      # export
      if [ "${summary_flag}" = "no-summary" ] || [ "${summary_flag}" = "default" ]; then
        cp "${pcap}" "${path_to_this_export}";
      fi
      # summaries
      if [ "${summary_flag}" = "summary-only" ] || [ "${summary_flag}" = "default" ]; then
        this_summary_pcap="summary.${summary_count}.pcap";
        pcap_size=$(du -b ${pcap} | cut -f1);
        if [ "${pcap_size}" -gt "${this_merge_limit}" ]; then
          # this single pcap is larger than the size limit
          if [ ${#merge_buffer[@]} -gt 0 ]; then
            # if merge_buffer > 0, merge the buffer
            echo "merging ${#merge_buffer[@]} pcaps, $(human_filesize ${merge_buffer_size}), ${path_to_this_export}${this_summary_pcap}";
            mergecap -F pcap -w "${path_to_this_export}${this_summary_pcap}" ${merge_buffer[*]};
            gzip "${path_to_this_export}${this_summary_pcap}";
            ((summary_count++));
            this_summary_pcap="summary.${summary_count}.pcap";
            merge_buffer=();
            merge_buffer_size=0;
            if [ -f "${merge_buffer_temp_name}" ]; then
              rm -f "${merge_buffer_temp_name}";
              merge_buffer_temp_name="";
            fi
          fi
          cp "${pcap}" "${path_to_this_export}${this_summary_pcap}.gz";
          ((summary_count++));
        elif [ "$(( ${pcap_size} + ${merge_buffer_size} ))" -gt "${this_merge_limit}" ]; then
          # this pcap would put the buffer over the size limit
          echo "merging ${#merge_buffer[@]} pcaps, $(human_filesize ${merge_buffer_size}), ${path_to_this_export}${this_summary_pcap}";
          mergecap -F pcap -w "${path_to_this_export}${this_summary_pcap}" ${merge_buffer[*]};
          gzip "${path_to_this_export}${this_summary_pcap}";
          ((summary_count++));
          if [ -f "${merge_buffer_temp_name}" ]; then
            rm -f "${merge_buffer_temp_name}";
            merge_buffer_temp_name="";
          fi
          merge_buffer=( "${pcap}" );
          merge_buffer_size="${pcap_size}";
        else
          # this pcap will fit in the buffer
          if [ ${#merge_buffer[@]} -le 49 ]; then
            # if the buffer is less than 49 pcaps, add to buffer
            merge_buffer+=( "${pcap}" );
            merge_buffer_size=$(( ${merge_buffer_size} + ${pcap_size} ));
          else
            # if the buffer is > 49 pcaps, do a temp merge
            merge_buffer_temp_name="${path_to_this_export}${this_summary_pcap}.temp";
            echo "merging ${#merge_buffer[@]} pcaps, $(human_filesize ${merge_buffer_size}), ${merge_buffer_temp_name}_buffer";
            mergecap -F pcap -w "${merge_buffer_temp_name}_buffer" ${merge_buffer[*]};
            mv "${merge_buffer_temp_name}_buffer" "${merge_buffer_temp_name}";
            merge_buffer=( "${merge_buffer_temp_name}" );
            merge_buffer+=( "${pcap}" );
            merge_buffer_size=$(( ${merge_buffer_size} + ${pcap_size} ));
          fi
        fi
      fi
    done
    
    if [ ${#merge_buffer[@]} -gt 0 ]; then
      # if merge_buffer > 0, merge the buffer
      this_summary_pcap="summary.${summary_count}.pcap";
      echo "merging ${#merge_buffer[@]} pcaps, $(human_filesize ${merge_buffer_size}), ${path_to_this_export}${this_summary_pcap}";
      mergecap -F pcap -w "${path_to_this_export}${this_summary_pcap}" ${merge_buffer[*]};
      gzip "${path_to_this_export}${this_summary_pcap}";
      ((summary_count++));
      merge_buffer=();
      merge_buffer_size=0;
      if [ -f "${merge_buffer_temp_name}" ]; then
        rm -f "${merge_buffer_temp_name}";
        merge_buffer_temp_name="";
      fi
    fi
  fi
  
  printf "\n ${_C4}EXPORT COMPLETED${_C0}\n";
  printf " export range: ${_C3}%24s${_C0} <=> ${_C3}%24s${_C0}\n" ${from} ${to};
  printf " ${_C3}%d${_C0} years | ${_C3}%d${_C0} months | ${_C3}%d${_C0} days | ${_C3}%d${_C0} hours | ${_C3}%d${_C0} minutes\n" ${time_span_in_years_aprox} ${time_span_in_months_aprox} ${time_span_in_days} ${time_span_in_hours} ${time_span_in_minutes};
  printf " ${_C3}%d${_C0} pcaps in export\n" ${#pcaps_to_export[@]};
  case "${summary_flag}" in
    (default)
      printf " exported: ${_C3}%d${_C0} pcaps\n" ${#pcaps_to_export[@]};
      printf " created ${_C3}%d${_C0} summary pcaps, limited to ${_C3}%s${_C0} each\n" ${summary_count} "$(human_filesize ${this_merge_limit})";
      ;;
    (no-summary)
      printf " exported: ${_C3}%d${_C0} pcaps\n" ${#pcaps_to_export[@]};
      ;;
    (summary-only)
      printf " created ${_C3}%d${_C0} summary pcaps, limited to ${_C3}%s${_C0} each\n" ${summary_count} "$(human_filesize ${this_merge_limit})";
      ;;
    (*)
      ;;
  esac
  printf "\n export path: ${_C3}%s${_C0}\n" "${path_to_this_export}";
  printf "\n        size: ${_C3}%s${_C0}\n" "$(human_filesize $(du -b ${path_to_this_export} | cut -f 1))";
  echo "";
}

##########################
### structure FUNCTIONS #
########################

_build_structure(){
  local silent="false"
  if [ "${#1}" -gt 0 ]; then silent="true"; fi

  # this is a list of all the base _PATH used by the script
  local path_array=( "${_PATH_TO_PCV_LOGS}" "${_PATH_TO_VAULTS}" "${_PATH_TO_VAULT}" "${_PATH_TO_VAULT_LOGS}" "${_PATH_TO_VAULT_PCAPS}" "${_PATH_TO_VAULT_PCAPS_RAW}" "${_PATH_TO_VAULT_PCAPS_INPUT}" "${_PATH_TO_VAULT_PCAPS_ARCHIVE}" "${_PATH_TO_VAULT_PCAPS_EXPORT}")
  # this is a list of all the base FILES used by the script 
  local file_array=( "${_PCV_LOG_MAIN}" "${_VAULT_LOG_MAIN}" "${_VAULT_LOG_TCPDUMP}" "${_VAULT_PID_TCPDUMP_FILE}" "${_VAULT_PID_PROCESSING_FILE}" )
  local p
  local f
  local p_created=()
  local f_created=()

   # verify each _PATH exists, if not create it
  for p in "${path_array[@]}"; do
    if [ ! -d "${p}" ]; then
      mkdir -p "${p}";
      p_created+=( "${p}" )
      if ( ! "${silent}" ); then printf " ... ${_C2}creating${_C0} ${p}\n"; fi
    fi
  done

  # verify each FILE exists, if not create it
  for f in "${file_array[@]}"; do
    if [ ! -f "${f}" ]; then
      touch "${f}";
      f_created+=( "${f}" )
      if ( ! "${silent}" ); then printf " ... ${_C2}creating${_C0} ${f}\n"; fi
    fi  
  done

  # log if any _PATH was created
  if [ "${#p_created[@]}" -gt 0 ]; then
    _log "status" "pcv" "${FUNCNAME[0]}" "directories.created" "'${p_created[*]}'"
  fi

  # log if any FILE was created
  if [ "${#f_created[@]}" -gt 0 ]; then
    _log "status" "pcv" "${FUNCNAME[0]}" "files.created" "'${f_created[*]}'"
  fi
}

_new_vault(){
  local vault="${1}"
  local interface="${2}"

  printf " ${_C4} pcapvault -new vault ... %24s ${_C0}\n" "${vault}"
  
  if [ $(_is_vault "${vault}") ]; then
    printf " ${vault} ${_C3}already exists${_C0} ...\n";
  else
    printf " ... ${_C2}creating${_C0} ${vault}\n";
  fi

  if [ ! -z "${interface}" ] && [ $(_is_interface "${interface}") ]; then
    _set_interface "${interface}";
    printf " ... ${_C2}setting${_C0} capture interface to ${_C2}${interface}${_C0}\n";
  fi

  printf " ... ${_C2}checking${_C0} file structures\n";
  
  _get_vault "${vault}"
  _build_structure
  
  printf " ${_C2}${vault}${_C0} is ready ...\n";
}

####################
### -ts FUNCTIONS #
##################

_check_date(){
  printf " ${_C4} DATE INPUT %s ${_C0}\n" $( [ "${1}" == "-examples" ] && echo "EXAMPLES" || echo "TEST" )
  printf " ${_C5}%24s${_C0} | ${_C5}%24s${_C0} | ${_C5}%7s${_C0}\n" "input" "output" "test";  

  if [ "${1}" == "examples" ]; then
    local edt=$(date "+%FT%T%z");
    for ((i=1; i <= "${#edt}"; i++ )); do
      dt=$(_iso8601_dt "${edt:0:$i}")
      if [ "${#dt}" -gt 0 ]; then
        printf " ${_C2}%24s${_C0} | ${_C2}%24s${_C0} | ${_C2}%7s${_C0}\n" "${edt:0:$i}" "${dt}" "vaild"
      else
        printf " %24s | %24s | %7s\n" "${edt:0:$i}" "${dt}" "invalid"
      fi
    done
  else
    local dt=$(_iso8601_dt "${1}")
    if [ "${#dt}" -gt 0 ]; then 
      printf " ${_C2}%24s${_C0} | ${_C2}%24s${_C0} | ${_C2}%7s${_C0}\n" "${1}" "${dt}" "vaild"
    else
      printf " %24s | %24s | ${_C1}%7s${_C0}\n" "${1}" "${dt}" "invalid"
    fi
  fi
}


#####################
### _main FUNCTION #
###################

_main(){

  _config
  _build_structure "silent"

  local arg=("$@");
  local to;
  local from;
  local export_pcap_summary_flag;
  local export_pcap_summary_size;

  case "${arg[0]}" in
    (-start)
      # -start [vaultName]
      if [ "${arg[1]}" == "--help" ]; then
        printf " ${_C4} pcapvault -start --help ... ${_C0}\n";
        printf " pcapvault ${_C2}-start${_C0} [${_C2}vaultname${_C0}] # ${_C3}start tcpdump and processing for named vault, using the default interface${_C0}\n";      
        printf " pcapvault ${_C2}-start${_C0} [${_C2}vaultname${_C0}] [${_C2}interface${_C0}] # ${_C3}start tcpdump and processing for named vault, using the named interface${_C0}\n";      
      elif [ ! -z $(_is_vault "${arg[1]}") ]; then
        if [ ! -z $(_is_interface "${arg[2]}") ]; then
          # interface provided
          _start "${arg[1]}" "${arg[2]}"
        else
          # no interface provided
          _start "${arg[1]}"
        fi
      else
        printf " pcapvault ${_C1}uknown argument${_C0}, -start '${arg[1]}'; ${_C3}try -start --help${_C0} \n";
      fi
      ;;
    (-stop)
      # -stop [vaultName]
      if [ "${arg[1]}" == "--help" ]; then
        printf " ${_C4} pcapvault -stop --help ... ${_C0}\n";
        printf " pcapvault ${_C2}-stop${_C0} [${_C2}vaultname${_C0}] # ${_C3}stops tcpdump and processing for named vault${_C0}\n";
      elif [ ! -z $(_is_vault "${arg[1]}") ]; then
        _stop "${arg[1]}"      
      else
        printf " pcapvault ${_C1}uknown argument${_C0}, -stop '${arg[1]}'; ${_C3}try -stop --help${_C0} \n";
      fi
      ;;
    (-list)
      # -list vaults
      case "${arg[1]}" in
        (vaults)
          _list_vaults
          ;;
        ('--help')
          printf " ${_C4} pcapvault -list --help ... ${_C0}\n";
          printf " pcapvault ${_C2}-list${_C0} ${_C2}vault${_C0} # ${_C3}lists all vaults${_C0}\n";
          ;;
        (*)
          printf " pcapvault ${_C1}uknown argument${_C0}, -list '${arg[1]}'; ${_C3}try -list --help${_C0} \n";
          ;;
      esac
      ;;
    (-setup)
      # -setup vault [vaultName]
      case "${arg[1]}" in
        (vault)
          if [[ "${arg[2]}" =~ ^[a-zA-Z0-9]+$ ]];
            then
              if [ ! -z "${arg[3]}" ] && [ ! -z $(_is_interface "${arg[3]}") ]; then
                # interface provided
                _new_vault "${arg[2]}" "${arg[3]}"
              else
                # no interface provided
                _new_vault "${arg[2]}";
              fi
            else printf " pcapvault ${_C1}invalid argument${_C0}, -setup vault '${arg[2]}'; ${_C3}vault name must be alphanumeric${_C0} \n"; exit 1; fi
          ;;
        ('--help')
          printf " ${_C4} pcapvault -setup --help ... ${_C0}\n";
          printf " pcapvault ${_C2}-setup${_C0} ${_C2}vault${_C0} [${_C2}alphanumeric${_C0}] # ${_C3}builds dir structure for named vault${_C0}\n";
          printf " pcapvault ${_C2}-setup${_C0} ${_C2}vault${_C0} [${_C2}alphanumeric${_C0}] [${_C2}interface${_C0}] # ${_C3}builds dir structure for named vault, with interface${_C0}\n";
          ;;
        (*)
          printf " pcapvault ${_C1}uknown argument${_C0}, -setup '${arg[1]}'; ${_C3}try -setup --help${_C0} \n";
          ;;
      esac
      ;;
    (-cleanup)
      # -cleanup [vault] full
      # -cleanup [vault] [from] [to]
      if [ "${arg[1]}" == "--help" ]; then
        printf " ${_C4} pcapvault -cleanup --help ... ${_C0}\n";
        printf " pcapvault ${_C2}-cleanup${_C0} [${_C2}vault${_C0}] [${_C2}full${_C0}] # ${_C3}deletes a vault's full directory structure${_C0}\n";
        printf " pcapvault ${_C2}-cleanup${_C0} [${_C2}vault${_C0}] [${_C2}from_date${_C0}] [${_C2}to_date${_C0}] # ${_C3}deletes pcaps in range from vault${_C0}\n";
      elif [ ! -z $(_is_vault "${arg[1]}") ]; then
        case "${arg[2]}" in
          (full)
            # cleanup a vault's full directory structure
            _get_vault "${arg[1]}"
            rm -rf "${_PATH_TO_VAULT_PCAPS_RAW}"
            rm -rf "${_PATH_TO_VAULT_PCAPS_INPUT}"
            rm -rf "${_PATH_TO_VAULT_PCAPS_ARCHIVE}"
            rm -rf "${_PATH_TO_VAULT_PCAPS_EXPORT}"
            mkdir -p "${_PATH_TO_VAULT_PCAPS_RAW}"
            mkdir -p "${_PATH_TO_VAULT_PCAPS_INPUT}"
            mkdir -p "${_PATH_TO_VAULT_PCAPS_ARCHIVE}"
            mkdir -p "${_PATH_TO_VAULT_PCAPS_EXPORT}"
            printf " ${_C2}full cleanup${_C0} of vault ${_C3}${arg[1]}${_C0} all pcaps deleted\n";
            _log "status" "vault" "${FUNCNAME[0]}" "FULL CLEANUP" "all ${arg[1]} pcaps deleted";
            ;;
          (*)
            from=$(_iso8601_dt "${arg[2]}");
            if [ "${#from}" -gt 0 ]; then
              to=$(_iso8601_dt "${arg[3]}");
            
              if [ "${#to}" -gt 0 ] && [ $(date -u -d "${from}" "+%s") -le $(date -u -d "${to}" "+%s") ]; then
                # cleanup vault pcap archive $from $to
                _get_vault "${arg[1]}";
                _cleanup "${from}" "${to}";
                from=$(date -u -d "${from}" "+%FT%H:%M:00%z");
                to=$(date -u -d "${to}" "+%FT%H:%M:00%z");
                _log "status" "vault" "${FUNCNAME[0]}" "CLEANUP.range" "'${from}' to '${to}'";
              else
                printf " pcapvault ${_C1}invalid date${_C0}, -cleanup '${arg[1]}' '${arg[2]}' '${arg[3]}' # ${_C3}try -cleanup --help, or -ts --help${_C0} \n";
              fi
            else
              printf " pcapvault ${_C1}invalid date${_C0}, -cleanup '${arg[1]}' '${arg[2]}' '${arg[3]}' # ${_C3}try -cleanup --help, or -ts --help${_C0} \n";
            fi
            ;;
        esac
      else
        printf " pcapvault ${_C1}vault not found${_C0}, -cleanup '${arg[1]}' # ${_C3}try -cleanup --help${_C0} \n";
      fi
      ;;
    (-export)
      # -export [vault] [from] [to]
      # -export [vault] [from] [to] <50> <summary-only> 
      # -export [vault] [from] [to] <no-summary> 
      if [ "${arg[1]}" == "--help" ]; then
        printf " ${_C4} pcapvault -export --help ... ${_C0}\n";
        printf " pcapvault ${_C2}-export${_C0} [${_C2}vault${_C0}] [${_C2}from_date${_C0}] [${_C2}to_date${_C0}] # ${_C3}export pcaps in range from vault${_C0}\n";
        printf " pcapvault -export [vault] [from_date] [to_date] <${_C2}summary_size${_C0}> # ${_C3}summary pcap file size limit in MB [range 10...4000], default=${_EXPORT_PCAP_SUMMARY_SIZE}${_C0}\n";
        printf " pcapvault -export [vault] [from_date] [to_date] <summary_size> <${_C2}summary-only${_C0}>  # ${_C3}the export will only contain summary pcaps${_C0}\n";
        printf " pcapvault -export [vault] [from_date] [to_date] <${_C2}no-summary${_C0}> # ${_C3}the export will only contain copies of the archive pcaps, no summary pcaps${_C0}\n";

      elif [ ! -z $(_is_vault "${arg[1]}") ]; then
        from=$(_iso8601_dt "${arg[2]}")
        if [ "${#from}" -gt 0 ]; then
          to=$(_iso8601_dt "${arg[3]}");
          if [ "${#to}" -gt 0 ] && [ $(date -u -d "${from}" "+%s") -le $(date -u -d "${to}" "+%s") ]; then
            # dates provided are good
            if [[ "${arg[4]}" =~ ^[0-9]+$ ]] && [ "${arg[4]}" -ge 10 ] && [ "${arg[4]}" -le 4000 ]; then
              # export pcap summary size provided
              export_pcap_summary_size="${arg[4]}";
              if [ "${arg[5]}" = "summary-only" ]; then export_pcap_summary_flag="${arg[5]}"; fi
            elif [ "${arg[4]}" = "no-summary" ]; then export_pcap_summary_size="${_EXPORT_PCAP_SUMMARY_SIZE}"; export_pcap_summary_flag="${arg[4]}";
            elif [ "${arg[4]}" = "summary-only" ]; then export_pcap_summary_size="${_EXPORT_PCAP_SUMMARY_SIZE}"; export_pcap_summary_flag="${arg[4]}";
            else export_pcap_summary_size="${_EXPORT_PCAP_SUMMARY_SIZE}"; export_pcap_summary_flag="default"; fi
            _get_vault "${arg[1]}";
            _export "${from}" "${to}" "${export_pcap_summary_size}" "${export_pcap_summary_flag}";
          else
            printf " pcapvault ${_C1}invalid date${_C0}, -export '${arg[1]}' '${arg[2]}' '${arg[3]}' # ${_C3}try -export --help, or -ts --help${_C0} \n";
          fi
        else
          printf " pcapvault ${_C1}invalid date${_C0}, -export '${arg[1]}' '${arg[2]}' '${arg[3]}' # ${_C3}try -export --help, or -ts --help${_C0} \n";
        fi
      else
        printf " pcapvault ${_C1}vault not found${_C0}, -export '${arg[1]}' # ${_C3}try -export --help${_C0} \n";
      fi
      ;;
    (-ts)
      # -ts date help
      # -ts date examples
      # -ts date [YYYY <-> YYYY-MM-DDTHH:MM:SS±TZNE]
      case "${arg[1]}" in
        ('date')
          _check_date "${arg[2]}"
          ;;
        ('--help')
          printf " ${_C4} pcapvault -ts --help ... ${_C0}\n";
          printf " pcapvault ${_C2}-ts${_C0} ${_C2}date${_C0} [${_C2}YYYY${_C0}<->${_C2}YYYY-MM-DDTHH:MM:SS±TZNE${_C0}] # ${_C3}checks to see if a date input is valid${_C0}\n";
          printf " pcapvault ${_C2}-ts${_C0} ${_C2}date${_C0} ${_C2}examples${_C0} # ${_C3}prints acceptable date input examples${_C0}\n";
          ;;
        (*)
          printf " pcapvault ${_C1}uknown argument${_C0}, -ts '${arg[1]}'; ${_C3}try -ts --help${_C0} \n";
          ;;
      esac
      ;;
    ('--help')
      printf " ${_C4} pcapvault --help ... ${_C0}\n";
      printf " pcapvault ${_C2}-setup${_C0} ${_C2}--help${_C0} # ${_C3}prep a vault for capturing${_C0}\n";
      printf " pcapvault ${_C2}-list${_C0} ${_C2}--help${_C0} # ${_C3}list vaults${_C0}\n";
      printf " pcapvault ${_C2}-start${_C0} ${_C2}--help${_C0} # ${_C3}start capturing and processing pcaps${_C0}\n";
      printf " pcapvault ${_C2}-stop${_C0} ${_C2}--help${_C0} # ${_C3}stop capturing and processing pcaps${_C0}\n";
      printf " pcapvault ${_C2}-cleanup${_C0} ${_C2}--help${_C0} # ${_C3}storage maintenance${_C0}\n";
      printf " pcapvault ${_C2}-export${_C0} ${_C2}--help${_C0} # ${_C3}export pcaps from a vault${_C0}\n";
      printf " pcapvault ${_C2}-ts${_C0} ${_C2}--help${_C0} # ${_C3}troubleshooting${_C0}\n";
      ;;
    (*)
      printf " pcapvault ${_C1}uknown argument${_C0}, '${arg[0]}'; ${_C3}try --help${_C0} \n";
      ;;
  esac
}

_main "$@"