#!/bin/bash

################################################################################
# GET MILK
# A tool to export all tasks from Remember The Milk to a file that todo.sh
# can use.
#
# Please see the README file for some additional information
#
# Author: Jacobo de Vera 
#         http://blog.jacobodevera.com
# 
#         Sun Apr 12 2009
#
################################################################################



## Please apply for your own API key and shared secret and paste them here.
## http://www.rememberthemilk.com/services/api/requestkey.rtm'
#
RTM_API_KEY='1234567890'
RTM_SHARED_SECRET='12345'

## WARNING: If you don't use xsltproc, you might need to change the 
## xslt_transform function below to match the syntax of your preferred
## XSLT processor.
#
XSLT_PROCESSOR='xsltproc'

function xslt_transform()
{
    stylesheet=$1
    input_file=$2
    output_file=$3

    $XSLT_PROCESSOR $stylesheet $input_file > $output_file
}


## I am not particularly keen on mixing functions with "constants" declarations
## but I wanted to have all the variable configuration together, so that I could
## have a warning like this:


################################################################################
##
##            WARNING: PLEASE DO NOT EDIT BELOW THIS LINE
##
## (Unless, of course, you want to hack this, in which case, be my guest)
##
################################################################################


RTM_REST_URL='http://api.rememberthemilk.com/services/rest/'
RTM_AUTH_URL='http://www.rememberthemilk.com/services/auth/'
RTM_API_KEY_REQ_URL='http://www.rememberthemilk.com/services/api/requestkey.rtm'


RTM_METHOD_GETFROB='rtm.auth.getFrob'
RTM_METHOD_GETTOKEN='rtm.auth.getToken'
RTM_METHOD_GETALLTASKS='rtm.tasks.getList'
RTM_METHOD_GETALLLISTS='rtm.lists.getList'


TMP_TASKS_FILE_XML='tmp_tasks.xml'
TMP_LISTS_FILE_XML='tmp_lists.xml'

TMP_TASKS_FILE_TXT='tmp_tasks.txt'
TMP_LISTS_FILE_TXT='tmp_lists.txt'


function check_config()
{
    if [ $RTM_API_KEY == '1234567890' ] || [ $RTM_SHARED_SECRET == '12345' ]
    then
        echo "ERROR: Your API key and/or your \"shared secret\" are invalid."
        echo " Please request your own API key from RTM. Both your API key and"
        echo " your shared secret will be emailed to you."
        echo " You can then paste them in the corresponding fields at the top"
        echo " of this script."
        echo ""
        echo "I will try now to take you to the RTM page where you can request"
        echo "your API key."
        open_url "$RTM_API_KEY_REQ_URL"
        exit 1
    fi
}


function check_dependencies()
{
    which $XSLT_PROCESSOR > /dev/null 2>&1
    [ $? -ne 0 ] && errormsg="${errormsg}- Could not find $XSLT_PROCESSOR\n"
    which awk > /dev/null 2>&1
    [ $? -ne 0 ] && errormsg="${errormsg}- Could not find awk\n"
    which sed > /dev/null 2>&1
    [ $? -ne 0 ] && errormsg="${errormsg}- Could not find sed\n"
    which curl > /dev/null 2>&1
    [ $? -ne 0 ] && errormsg="${errormsg}- Could not find curl\n"
    which md5sum > /dev/null 2>&1
    [ $? -ne 0 ] && errormsg="${errormsg}- Could not find md5sum\n"

    if [ ! -z "$errormsg" ]; then
        echo "ERROR: One or more dependencies missing:"
        echo -en $errormsg
        exit 1
    fi
}


function open_url()
{
    URL=$1
    ## This is a slightly modified version of Philippe Teuwen's code for a todo.txt
    ## action called nav that can be found here:
    ## http://github.com/doegox/todo.txt-cli/blob/extras/todo.actions.d/nav

    # Trying to be smart...
    # on Debian alike:
    if $(which x-www-browser >/dev/null 2>&1); then
        x-www-browser "$URL" &
    # with freedesktop.org utils:
    elif $(which xdg-open >/dev/null 2>&1); then
        xdg-open "$URL" &
    # if you have git:
    elif [ -x /usr/lib/git-core/git-web--browse ]; then
        /usr/lib/git-core && ./git-web--browse "$URL" &
    # last resort, a mano...
    elif $(which firefox >/dev/null 2>&1); then
        firefox "$URL" &
    elif $(which konqueror >/dev/null 2>&1); then
        konqueror "$URL" &
    elif $(which nautilus >/dev/null 2>&1); then
        nautilus "$URL" &
    # Windowsien?
    elif [ -x "/cygdrive/c/Program Files/Mozilla Firefox/firefox.exe" ]; then
        "/cygdrive/c/Program Files/Mozilla Firefox/firefox.exe" "$URL" &
    # OS X?
    elif [ -x "/usr/bin/open" ]; then
        "/usr/bin/open" "$URL" &
    else
        echo "Sorry I'm giving up, cannot find your browser :-("
        echo ""
        echo "Please point your browser to the following URL to allow access to your RTM account:" 
        echo "$URL"
    fi
}


function _sticktogether
{
    awk -v ORS="" '{print}'
    echo ""
}


function _sign()
{
    s=`echo "$1" | sed 's/[=&]//g'`
    echo -n "${RTM_SHARED_SECRET}${s}" | md5sum | awk '{print $1}' 
}


function check_accepted()
{
    token_resp=$1
    stat=`echo "$token_resp" | sed -n 's/<rsp stat="\(.*\)">.*$/\1/p'`
    if [ "$stat" == 'fail' ]
    then
        echo "ERROR: I am not authorised to access your RTM account."
        echo "Please rerun again."
        exit 1
    fi
}


function make_signed_url()
{
    url_base=$1
    shift
    tmp_file="tmp_sort.txt"
    while [ "$#" -gt 0 ]
    do
        key=$1
        value=$2
        shift 2
        query="$query&$key=$value"
        echo -e "$key\t$value" >> $tmp_file
    done
    ## parameters need to be sorted for signing
    sq=`cat $tmp_file | sort -k1 | sed 's/\t//' | _sticktogether`
    rm $tmp_file
    signature=`_sign $sq`
    query="$query&api_sig=$signature"
    url="$url_base?${query:1}"
    echo $url

}


function process_list()
{
    tmp_xslt_file='lists_tmp.xsl'
    cat << EOX > $tmp_xslt_file

    <xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
    <xsl:strip-space elements="*"/>
    <xsl:output method="text" encoding="UTF-8"/>

    <!--<xsl:template match="lists">
    <xsl:apply-templates select="list"/>
    </xsl:template>-->

    <xsl:template match="list">
        <xsl:if test="@archived = 0">
            <xsl:if test="@locked = 0">
                <xsl:value-of select="@id"/>
                <!--<xsl:text>&#9;</xsl:text>-->
                <xsl:text> </xsl:text>
                <xsl:value-of select="@name"/>
                <xsl:text>&#xa;</xsl:text>
            </xsl:if>
        </xsl:if>
    </xsl:template>

    </xsl:stylesheet>
EOX
    xslt_transform $tmp_xslt_file $TMP_LISTS_FILE_XML $TMP_LISTS_FILE_TXT
    sed -i -e 's/ /_/g' -e 's/_/ /' $TMP_LISTS_FILE_TXT
    sort -k1 -o $TMP_LISTS_FILE_TXT $TMP_LISTS_FILE_TXT
    rm -f $tmp_xslt_file
}


function process_tasks()
{
    tmp_xslt_file='tasks_tmp.xsl'
    cat << EOX > $tmp_xslt_file
    <xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
    <xsl:strip-space elements="*"/>
    <xsl:output method="text" encoding="UTF-8"/>

    <xsl:template match="list">
    <xsl:apply-templates select="taskseries/task"/>
    </xsl:template>

    <xsl:template match="task">
        <xsl:if test="string-length(@completed)=0">
            <xsl:value-of select="../../@id"/>
            <xsl:text> </xsl:text>

            <xsl:call-template name="priority">
                <xsl:with-param name="pri" select="@priority"/>
            </xsl:call-template> 

            <xsl:value-of select="substring(@added, 0, 11)"/>
            <xsl:text> </xsl:text>
            <xsl:value-of select="../@name"/>
            <xsl:apply-templates select="../tags/tag"/>
            <xsl:text>&#xa;</xsl:text>
        </xsl:if>
    </xsl:template>

    <xsl:template name="priority">
        <xsl:param name="pri"/>
        <xsl:choose>
            <xsl:when test="\$pri = '1'">
                <xsl:text>(A) </xsl:text>
            </xsl:when>
            <xsl:when test="\$pri = '2'">
                <xsl:text>(B) </xsl:text>
            </xsl:when>
            <xsl:when test="\$pri = '3'">
                <xsl:text>(C) </xsl:text>
            </xsl:when>
        </xsl:choose>
    </xsl:template>

    <xsl:template  match="tag">
        <xsl:text> @</xsl:text>
        <xsl:value-of select="."/>
    </xsl:template>

    </xsl:stylesheet>
EOX
    xslt_transform $tmp_xslt_file $TMP_TASKS_FILE_XML $TMP_TASKS_FILE_TXT
    sort -k1 -o $TMP_TASKS_FILE_TXT $TMP_TASKS_FILE_TXT
    rm -f $tmp_xslt_file
}


## THE REAL STORY BEGINS HERE
################################################################################


## INITIAL CHECKS
#-------------------------------------------------------------------------------
if [ $# -ne 1 ]; then
    echo "ERROR: Output file name missing"
    echo ""
    echo "USAGE: $0 output_file"
    exit 1
fi
todo_txt_out_file=$1

check_dependencies
check_config


## GET THE FROB
#-------------------------------------------------------------------------------
frob_url=`make_signed_url "$RTM_REST_URL" api_key "$RTM_API_KEY" method "$RTM_METHOD_GETFROB"`
frob=`curl -s "$frob_url" | sed -n 's/^.*<frob>\([^<]*\)<\/frob>.*$/\1/p'`


## GET AUTHORISATION
#-------------------------------------------------------------------------------

auth_url=`make_signed_url "$RTM_AUTH_URL" api_key "$RTM_API_KEY" frob "$frob" perms read`
open_url "$auth_url"

echo "Please authorise access to your RTM accound and then press enter."
read 

## GET THE TOKEN
#-------------------------------------------------------------------------------

token_url=`make_signed_url "$RTM_REST_URL" \
                api_key "$RTM_API_KEY" \
                method "$RTM_METHOD_GETTOKEN"\
                frob "$frob"`
resp_token=`curl -s "$token_url"`
check_accepted "$resp_token"
token=`echo -e $resp_token | sed -n 's/^.*<token>\(.*\)<\/token>.*$/\1/p'`


## GET THE LISTS OF TASKS (i.e., the projects)
#-------------------------------------------------------------------------------

curl -s `make_signed_url $RTM_REST_URL api_key "$RTM_API_KEY" \
        auth_token "$token" \
        method "$RTM_METHOD_GETALLLISTS"` > $TMP_LISTS_FILE_XML


## GET THE TASKS
#-------------------------------------------------------------------------------

curl -s `make_signed_url $RTM_REST_URL api_key "$RTM_API_KEY" \
        auth_token "$token" \
        method "$RTM_METHOD_GETALLTASKS"` > $TMP_TASKS_FILE_XML


## CONVERT LISTS XML TO SIMPLE TXT
#-------------------------------------------------------------------------------

process_list


## CONVERT TASKS XML TO SIMPLE TXT
#-------------------------------------------------------------------------------

process_tasks


## FINAL FORMATTING
#-------------------------------------------------------------------------------

join $TMP_LISTS_FILE_TXT $TMP_TASKS_FILE_TXT | \
    sed 's/^[0-9]\+ \([^ ]\+\) \(.*\)$/\2 +\1/' > $todo_txt_out_file

echo "All pending tasks from RTM have been exported to $todo_txt_out_file."


## CLEAN UP
#-------------------------------------------------------------------------------

rm -f "$TMP_TASKS_FILE_TXT" "$TMP_LISTS_FILE_TXT" \
      "$TMP_TASKS_FILE_XML" "$TMP_LISTS_FILE_XML"

