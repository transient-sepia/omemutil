#!/usr/bin/env bash
#
# omemutil-chan
# version 1.0
#
# / that's me! all about excess! /
#

# os dependent
case $(uname) in
  "SunOS") SIZE=/usr/ccs/bin/size
           ORATAB=/var/opt/oracle/oratab
           INSTANCES=$(ps -eao comm | grep [o]ra_pmon | sed 's/ora_pmon_//g' | awk '{print $1}')
           ;;
  "Linux") SIZE=/usr/bin/size
           ORATAB=/etc/oratab
           INSTANCES=$(ps -eao command | grep [p]mon | sed 's/ora_pmon_//g' | grep -v sed | awk '{print $1}')
           ;;
  "AIX")   SIZE="/usr/bin/size -f -X 32_64"
           ORATAB=/etc/oratab
           INSTANCES=$(ps -eao args | grep [o]ra_pmon | sed 's/ora_pmon_//g' | awk '{print $1}')
           ;;
  "HP-UX") SIZE="/usr/bin/size"
           ORATAB=/etc/oratab
           INSTANCES=$(UNIX95= ps -eao args | grep [o]ra_pmon | sed 's/ora_pmon_//g' | awk '{print $1}')
           ;;
  *)       printf "Unknown OS.\n" && exit 13
           ;;
esac

# error handling
function errck () {
  printf "\n\n*** $(date +%Y.%m.%d\ %H:%M:%S)\n${ERRMSG} Stop.\n"
  exit 1
}

# set oracle environment
function setora () {
  ERRMSG="SID ${1} not found in ${ORATAB}."
  if [[ $(cat ${ORATAB} | grep "^$1:") ]]; then
    unset ORACLE_SID ORACLE_HOME ORACLE_BASE
    export ORACLE_BASE=/u01/app/oracle
    export ORACLE_SID=${1}
    export ORACLE_HOME=$(cat ${ORATAB} | grep "^${ORACLE_SID}:" | cut -d: -f2)
    export PATH=${ORACLE_HOME}/bin:${PATH}
  else
    errck
  fi
}

# check running instances
if [[ -z ${INSTANCES} ]]; then
    printf "No running instance(s), bye!\n" 
    exit 13
fi

# oratab
for ORACLE_SID in ${INSTANCES}; do
  ORACLE_HOME=$(cat ${ORATAB} | grep $ORACLE_SID | cut -d: -f2 | head -1)
  if [[ -z ${ORACLE_HOME} ]]; then
    printf "Can't determine \$ORACLE_HOME for instance ${SID}. Add correct record to your ${ORATAB} and try again.
Expected:
    \$ORACLE_SID:\$ORACLE_HOME:\<N\|Y\>:\n"
    exit 13
  fi
done

# oracle_home
for SID in ${INSTANCES}; do
  ALL_ORACLE_HOME="${ALL_ORACLE_HOME}$(cat ${ORATAB} | grep "^${SID}:" | cut -d: -f2)\n"
done
UNIQ_OH=$(printf "${ALL_ORACLE_HOME}" | sort | uniq)
TOTAL_UNIQ_OH=$(printf "${UNIQ_OH}\n" | wc -l)
printf "\n*** Oracle memory utilization ***\n"
for ORACLE_HOME in ${UNIQ_OH}; do
  for INSTANCE in ${INSTANCES}; do
    if [[ $(grep "${INSTANCE}:${ORACLE_HOME}" ${ORATAB}) ]]; then
      SORTED_SIDS="${SORTED_SIDS} ${INSTANCE}"
    fi
  done
  printf "\n**************************************************\n\$ORACLE_HOME=${ORACLE_HOME}\n\n"
  export ORACLE_HOME=${ORACLE_HOME}
  export PATH=$ORACLE_HOME/bin:$PATH
  unset NLS_LANG
  # binary size
  declare -a MARR
  case $(uname) in
    "SunOS") MARR=($(${SIZE} $ORACLE_HOME/bin/oracle | awk '{print $1,$3,$5}' ))
             ;;
    "Linux") MARR=($(${SIZE} $ORACLE_HOME/bin/oracle | awk '/^[0-9]/ {print $1,$2,$3}' ))
             ;;
    "AIX")   MARR=($(${SIZE} $ORACLE_HOME/bin/oracle | awk '{print $2,$4,$6}' | tr -d '().' | tr -d [:alpha:] ))
             ;;
    "HP-UX") MARR=($(${SIZE} $ORACLE_HOME/bin/oracle | awk '{print $1,$3,$5}' ))
             ;;
    *)       printf "Unknown error.\n" && exit 13
             ;;
  esac
  # uncomment to see memory size for binary
  # printf "text=${MARR[0]} b; data=${MARR[1]} b; bss=${MARR[2]} b\n"
  # subtract TEXT size for non-single instance
  if [[ $(printf "${SORTED_SIDS}" | wc -w) -gt 1 ]]; then
    TEXT=${MARR[0]} && unset MARR[0]
  fi
  # calculate memory for instance
  for ORACLE_SID in ${SORTED_SIDS}; do
    setora ${ORACLE_SID}
    PGASTAT=$(printf "
      set head off verify off trimspool on feed off line 2000 pagesize 100 newpage none
      set numformat 9999999999999999999
      set pages 0
      select statistic# from v\$statname where name = 'session pga memory';
      exit
    " | sqlplus -s / as sysdba | grep .)
    SUM=$(sqlplus -s "/ as sysdba" << EOS
set pagesize 0
select SGA+${MARR[0]}+(${MARR[1]}+${MARR[2]}+8192+2048)*N+PGA "Mtotal ${ORACLE_SID}"
from (select sum(value) SGA from v\$sga),
(select count(*) N, sum(value) PGA from v\$sesstat where statistic#=${PGASTAT} and 
sid != (select unique sid from v\$mystat));
EOS
)
    SUM=$(printf ${SUM}|awk '{printf "%.0f",$1}') 
    printf "${ORACLE_SID}  \t${SUM}" | awk '{print $1"       \t"$2/1048576" Mb"}'
    TOTAL=$((${TOTAL} + ${SUM}))
  done
TOTAL=$(( (${TEXT} + ${TOTAL})/1048576 ))
printf "${TOTAL}" | awk '{print "\t\t----------\nTotal:\t\t"$1" Mb"}'
unset SORTED_SIDS
unset MARR
done

# exit
exit 0
