
//**********************************************************************************************************************************
//
//   Purpose: Interoperability Tester source code file
//
//   Project: Everest
//
//  Filename: InteropTester.cpp
//
//   Authors: Caroline.M.Mathieson (CMM)
//
//**********************************************************************************************************************************
//
//  Description
//  -----------
//
//! \file InteropTester.cpp
//! \brief Contains the complete implementation of the Interoperability Tester.
//!
//**********************************************************************************************************************************

/** \mainpage

This windows sockets console application is designed to validate and performance test the project everest mitls.dll component. This
component is a formally verified implementation of the TLS 1.3 and QUIC (DTLS) protocol as defined in draft internet standard:-
https://tools.ietf.org/html/draft-ietf-tls-tls13-23 and later.

The tester must check that the component is compliant with this standard and to acheive this, it checks all the different cipher
suites, signature algorithms and named groups supported by the component. It also checks the component (running in client mode)
against other TLS/QUIC implementations. Full and partial handshakes are tested.

The component is generated from F* source code and converted to 'c' code by various tools also developed in the project. These tools
are under constant development and to ensure that their performance has not degraded and the performance of the resulting source
code has not degraded, the performance of the component needs to be measured and statistics recorded for reference. This way, any
regression in performance can be detected. A simple CSV file is generated to record these statistics.

**/

//**********************************************************************************************************************************

#include "stdafx.h"
#include "time.h"
#include "string.h"

#include "InteropTester.h"
#include "Tester.h"

#include "pngwriter.h"

//**********************************************************************************************************************************

// in simpleserver.cpp

extern void OpenConsoleCopyFile ( void );

extern void CloseConsoleCopyFile ( void );

//**********************************************************************************************************************************

class TLSTESTER *Tester = NULL; // The global tester object

char DateAndTimeString [ 23 ]; // DD:MM:YYYY at HH:MM:SS

// default filenames for the output files

char TesterDebugFileName          [ MAX_PATH ] = { "TesterDebug.log"          };
char ComponentStatisticsFileName  [ MAX_PATH ] = { "ComponentStatistics.csv"  };
char RecordedMeasurementsFileName [ MAX_PATH ] = { "RecordedMeasurements.csv" };

//**********************************************************************************************************************************

static char TitleText [] =
{
    "\n"
    "           TLS/DTLS Tester\n"
    "            Version 0.0.2\n"
    "(c) Microsoft Research 21st August 2018\n"
    "\n"
};

//**********************************************************************************************************************************

static char HelpText [] =
{
    "Usage: Tester.exe [Arguments...]\n"
    "\n"
    "  -v              Be verbose in console output (otherwise no console output except errors)\n"
    "  -d              Turn on console debugging output\n"
    "  -f:filename     Use file to specify server names (otherwise tester uses bing.com)\n"
    "  -c              Do libmitls as client TLS and DTLS tests\n"
    "  -s              Do libmitls as client & server TLS and DTLS tests\n"
    "  -i              Do libmitls as client interoperability TLS and DTLS tests\n"
    "  -x              Do libmitls as server interoperability TLS and DTLS tests\n"
    "  -t              Do TLS part of any tests\n"
    "  -q              Do QUIC part of any tests\n"
    "  -l:tlsversion   Specify TLS version number to support (default is '1.3')\n"
    "  -p:port number  Specify port number to use (default is 443)\n"
    "  -o:hostname     Specify host name to use (default is 'google.com')\n"
    "  -r:certfilename Use specified Server Certificate filename (default is built in)\n"
    "  -k:keyfilename  Use specified Server certificate key filename (default is built in)\n"
    "  -a:authfilename Use specified Certificate Authority Chain filename (default is built in\n"
    "\n"
};

//**********************************************************************************************************************************

static const int WheelTableSize = 4;
static int       Wheel          = 0; // start with the vertical bar

static char WheelTable [ WheelTableSize ] =
{
    '|',
    '/',
    '-',
    '\\'
};

//**********************************************************************************************************************************

static const char *WeekDays [] =
{
    "Sunday",
    "Monday",
    "Tuesday",
    "Wednesday",
    "Thursday",
    "Friday",
    "Saturday"
};

//**********************************************************************************************************************************

static const char *MonthDays [] =
{
    "0th",  "1st",  "2nd",  "3rd",  "4th",  "5th",  "6th",  "7th",  "8th",  "9th",
    "10th", "11th", "12th", "13th", "14th", "15th", "16th", "17th", "18th", "19th",
    "20th", "21st", "22nd", "23rd", "24th", "25th", "26th", "27th", "28th", "29th",
    "30th", "31st"
};

//**********************************************************************************************************************************

static const char *MonthNames [] =
{
    "January",
    "February",
    "March",
    "April",
    "May",
    "June",
    "July",
    "August",
    "September",
    "October",
    "November",
    "December",
};

//**********************************************************************************************************************************

FILE *OpenRecordedMeasurementsFile ( void )
{
    FILE      *RecordedMeasurementsFile = NULL;
    time_t     CurrentTime;
    struct tm *LocalTime;
    int        Count;
    char       TestRunTitle       [ 2000 ];
    char       TestRunUnderscores [ 2000 ];

    // write out the recorded measurements into a file

    RecordedMeasurementsFile = fopen ( RecordedMeasurementsFileName, "wt" );

    if ( RecordedMeasurementsFile != NULL )
    {
        //
        // print the date and time of this test run into the recorded measurements file
        //
        time ( &CurrentTime );

        LocalTime = localtime ( &CurrentTime );

        sprintf ( TestRunTitle,
                  "# Measurements recorded on %s %s of %s %4d at %02d:%02d:%02d\n",
                  WeekDays   [ LocalTime->tm_wday ],
                  MonthDays  [ LocalTime->tm_mday ],
                  MonthNames [ LocalTime->tm_mon  ],
                  LocalTime->tm_year + 1900,
                  LocalTime->tm_hour,
                  LocalTime->tm_min,
                  LocalTime->tm_sec );

        fprintf ( RecordedMeasurementsFile, TestRunTitle );

        //
        // Add an undercore consisting of '----' of the right length to the title
        //
        TestRunUnderscores [ 0 ] = '#';
        TestRunUnderscores [ 1 ] = ' ';

        for ( Count = 2; Count < ( strlen ( TestRunTitle ) - 1 ); )
        {
            TestRunUnderscores [ Count++ ] = '-';
        }

        TestRunUnderscores [ Count++ ] = '\n';
        TestRunUnderscores [ Count++ ] = '\0';

        fprintf ( RecordedMeasurementsFile, TestRunUnderscores );

        //
        // Print the heading for this set of statistics (test run)
        //
        fprintf ( RecordedMeasurementsFile,
                  "\n%s %s %s %s %s %s %s\n",
                  "Date & Time, ",
                  "Measurement Number, ",
                  "Cipher Suite, ",
                  "Signature Algorithm, ",
                  "Named Group, ",
                  "Pass/Fail, ",
                  "Execution Time (us)" );
    }

    return ( RecordedMeasurementsFile );
}

//**********************************************************************************************************************************

FILE *OpenStatisticsFile ( void )
{
    time_t     CurrentTime;
    struct tm *LocalTime;
    int        Count;
    FILE      *StatisticsFile = NULL;
    char       TestRunTitle       [ 2000 ];
    char       TestRunUnderscores [ 2000 ];

    //
    // Try to open the existing file in "append" mode so we keep the older stats, but if it does not exist then create a new one
    //
    StatisticsFile = fopen ( ComponentStatisticsFileName, "wt" ); // use "a" afterwards!

    if ( StatisticsFile != NULL )
    {
        //
        // print the date and time of this test run into the statistics file
        //
        time ( &CurrentTime );

        LocalTime = localtime ( &CurrentTime );

        sprintf ( TestRunTitle,
                  "# Test Run made on %s %s of %s %4d at %02d:%02d:%02d\n",
                  WeekDays   [ LocalTime->tm_wday ],
                  MonthDays  [ LocalTime->tm_mday ],
                  MonthNames [ LocalTime->tm_mon  ],
                  LocalTime->tm_year + 1900,
                  LocalTime->tm_hour,
                  LocalTime->tm_min,
                  LocalTime->tm_sec );

        fprintf ( StatisticsFile, TestRunTitle );

        //
        // Add an undercore consisting of '----' of the right length to the title
        //
        TestRunUnderscores [ 0 ] = '#';
        TestRunUnderscores [ 1 ] = ' ';

        for ( Count = 2; Count < ( strlen ( TestRunTitle ) - 1 ); )
        {
            TestRunUnderscores [ Count++ ] = '-';
        }

        TestRunUnderscores [ Count++ ] = '\n';
        TestRunUnderscores [ Count++ ] = '\0';

        fprintf ( StatisticsFile, TestRunUnderscores );

        //
        // Print the heading for this set of statistics (test run)
        //
        fprintf ( StatisticsFile,
                  "\n%s %s %s %s %s %s %s\n",
                  "Date & Time, ",
                  "Measurement Number, ",
                  "Cipher Suite, ",
                  "Signature Algorithm, ",
                  "Named Group, ",
                  "Pass/Fail, ",
                  "Execution Time (us)" );
    }

    return ( StatisticsFile );
}

//**********************************************************************************************************************************

FILE *OpenDebugFile ( void )
{
    time_t     CurrentTime;
    struct tm *LocalTime;
    int        Count;
    FILE      *File = NULL;
    char       TestRunTitle       [ 200 ];
    char       TestRunUnderscores [ 200 ];

    //
    // Try to create a new log file
    //
    File = fopen ( TesterDebugFileName, "wt" );

    if ( File != NULL )
    {
        //
        // print the data and time of this test run into the debug file
        //
        time ( &CurrentTime );

        LocalTime = localtime ( &CurrentTime );

        sprintf ( DateAndTimeString,
                  "%02d:%02d:%4d at %02d:%02d:%02d",
                  LocalTime->tm_wday,
                  LocalTime->tm_mday,
                  LocalTime->tm_year + 1900,
                  LocalTime->tm_hour,
                  LocalTime->tm_min,
                  LocalTime->tm_sec );

        sprintf ( TestRunTitle,
                  "Test Run made on %s %s of %s %4d at %02d:%02d:%02d\n",
                  WeekDays   [ LocalTime->tm_wday ],
                  MonthDays  [ LocalTime->tm_mday ],
                  MonthNames [ LocalTime->tm_mon  ],
                  LocalTime->tm_year + 1900,
                  LocalTime->tm_hour,
                  LocalTime->tm_min,
                  LocalTime->tm_sec );

        fprintf ( File, TestRunTitle );

        //
        // Add an undercore consisting of '----' of the right length to the title
        //
        for ( Count = 0; Count < ( strlen ( TestRunTitle ) - 1 ); )
        {
            TestRunUnderscores [ Count++ ] = '-';
        }

        TestRunUnderscores [ Count++ ] = '\n';
        TestRunUnderscores [ Count++ ] = '\n';
        TestRunUnderscores [ Count++ ] = '\0';

        fprintf ( File, TestRunUnderscores );
    }

    return ( File );
}

//**********************************************************************************************************************************

void OperatorConfidence ( void )

{
    printf ( "%c\r", WheelTable [ Wheel++ ] );

    if ( Wheel >= WheelTableSize )
    {
        Wheel = 0;
    }
}

//*********************************************************************************************************************************

void ProcessCommandLine ( int   ArgumentCount,
                          char *ArgumentList         [],
                          char *EnvironmentVariables [],
                          bool  Silent )
{
    int    Index     = 0;
    int    PathIndex = 0;
    char  *Address   = NULL;

    // print out the arguments

    for ( Index = 0; Index < ArgumentCount; Index++ )
    {
        if ( !Silent ) printf ( "Argument [%d] = %s\n", Index, ArgumentList [ Index ] );
    }

    // print out the environment variables

    for ( Index = 0; EnvironmentVariables [ Index ] != NULL; Index ++ )
    {
        if ( !Silent ) printf ( "EnvironmentVariables [%d] = %s\n", Index, EnvironmentVariables [ Index ] );

        // check if this is the path environment variable

        Address = strstr ( EnvironmentVariables [ Index ], "Path" );

        if ( Address == &EnvironmentVariables [ Index ] [ 0 ] ) // i.e. the first characters
        {
            PathIndex = Index; // we have found the path variable so record the index
        }
    }

    // print out the path in its sections if we found it

    if ( PathIndex != 0 )
    {
        // scan the path environment variable and seperate out the parts between the semicolons

        Index = 0;

        Address = strtok ( EnvironmentVariables [ PathIndex ], ";" );

        while ( Address != NULL )
        {
            if ( Index == 0 ) Address = &Address [ strlen ( "Path=" ) ]; // the very first one is slightly different

            if ( !Silent ) printf ( "Path Part [%02d] = %s\n", Index++, Address );

            Address = strtok ( NULL, ";" );
        }
    }
}

//**********************************************************************************************************************************

void GetTestParameters ( int   ArgumentCount,
                         char *ArgumentList         [],
                         char *EnvironmentVariables [],
                         bool  Silent  )
{
    if ( Tester != NULL ) // the tester object must exist when this function is called
    {
        for ( int Count = 1; Count < ArgumentCount; Count++ )
        {
            if ( ArgumentList [ Count ] [ 0 ] == '-' )
            {
                // start of command line argument so check what letter follows:-

                switch ( ArgumentList [ Count ] [ 1 ] )
                {
                    case 'v': // -v = enable verbose console output
                    {
                        Tester->VerboseConsoleOutput = TRUE;

                        break;
                    }

                    case 'd': // -d = turn on debugging
                    {
                        Tester->ConsoleDebugging = TRUE;

                        break;
                    }

                    case 'f': // -f:filename = specify a hostname file
                    {
                        Tester->UseHostList = TRUE;

                        // get filename of host list

                        strcpy ( Tester->HostFileName, &ArgumentList [ Count ] [ 3 ] ); // move past -f:

                        break;
                    }

                    case 'c': // -c = do client tests
                    {
                        Tester->DoClientTests =  TRUE;

                        break;
                    }

                    case 's': // -s = do server tests
                    {
                        Tester->DoServerTests = TRUE;

                        break;
                    }

                    case 'i': // -i = do client interoperability tests
                    {
                        Tester->DoClientInteroperabilityTests = TRUE;

                        break;
                    }

                    case 'x': // -x = do server interoperability tests
                    {
                        Tester->DoServerInteroperabilityTests = TRUE;

                        break;
                    }

                    case 't': // -t = do TLS tests
                    {
                        Tester->DoTLSTests = TRUE;

                        break;
                    }

                    case 'q': // -q = do QUIC tests
                    {
                        Tester->DoQUICTests = TRUE;

                        break;
                    }

                   case 'l': // -l:tlsversion = Specify TLS version number to support (default is '1.3')
                    {
                        // get TLS Version

                        strncpy ( Tester->TLSVersion, &ArgumentList [ Count ] [ 3 ], sizeof ( Tester->TLSVersion ) - 1 ); // move past -o:

                        break;
                    }
                    case 'p': // -p:PPP = Specify Port Number to use (default 443)
                    {
                        Tester->UsePortNumber = TRUE;

                        // get port number

                        Tester->PortNumber = atoi ( &ArgumentList [ Count ] [ 3 ] ); // move past -p:

                        break;
                    }

                    case 'o': // -o:hostname = Specify Host Name to use (default 'bing.com')
                    {
                        Tester->UseHostName = TRUE;

                        // get host name

                        strcpy ( Tester->HostName, &ArgumentList [ Count ] [ 3 ] ); // move past -o:

                        break;
                    }

                    case 'r': // -r:certfilename = Use specified Server Certificate filename
                    {
                        // get certificate filename

                        strcpy ( Tester->ServerCertificateFilename, &ArgumentList [ Count ] [ 3 ] ); // move past -r:

                        break;
                    }

                    case 'k': // -k:keyfilename = Use specified Server certificate key filename
                    {
                        // get certificate key filename

                        strcpy ( Tester->ServerCertificateKeyFilename, &ArgumentList [ Count ] [ 3 ] ); // move past -k:

                        break;
                    }

                    case 'a': // -k:Authfilename = Use specified Certificate Authority Chain filename
                    {
                        // get certificate authority chain filename

                        strcpy ( Tester->CertificateAuthorityChainFilename, &ArgumentList [ Count ] [ 3 ] ); // move past -a:

                        break;
                    }
               }
            }
        }

        // print out the resulting config if console output enabled

        if ( Tester->VerboseConsoleOutput )
        {
            printf ( "                 ConsoleDebugging = " ); if ( Tester->ConsoleDebugging              ) printf ( "TRUE\n" ); else printf ( "FALSE\n" );
            printf ( "                      UseHostList = " ); if ( Tester->UseHostList                   ) printf ( "TRUE\n" ); else printf ( "FALSE\n" );
            printf ( "                      UseHostName = " ); if ( Tester->UseHostName                   ) printf ( "TRUE\n" ); else printf ( "FALSE\n" );
            printf ( "                    UsePortNumber = " ); if ( Tester->UsePortNumber                 ) printf ( "TRUE\n" ); else printf ( "FALSE\n" );
            printf ( "                       DoTLSTests = " ); if ( Tester->DoTLSTests                    ) printf ( "TRUE\n" ); else printf ( "FALSE\n" );
            printf ( "                      DoQUICTests = " ); if ( Tester->DoQUICTests                   ) printf ( "TRUE\n" ); else printf ( "FALSE\n" );
            printf ( "                    DoClientTests = " ); if ( Tester->DoClientTests                 ) printf ( "TRUE\n" ); else printf ( "FALSE\n" );
            printf ( "                    DoServerTests = " ); if ( Tester->DoServerTests                 ) printf ( "TRUE\n" ); else printf ( "FALSE\n" );
            printf ( "    DoClientInteroperabilityTests = " ); if ( Tester->DoClientInteroperabilityTests ) printf ( "TRUE\n" ); else printf ( "FALSE\n" );
            printf ( "    DoServerInteroperabilityTests = " ); if ( Tester->DoServerInteroperabilityTests ) printf ( "TRUE\n" ); else printf ( "FALSE\n" );

            printf ( "                       TLSVersion = %s\n", Tester->TLSVersion );

            if ( Tester->UseHostList )
            {
                printf ( "                     HostFileName = %s\n", Tester->HostFileName );
            }
            else
            {
                printf ( "                         HostName = %s\n", Tester->HostName );
            }

            printf ( "                       PortNumber = %d\n", Tester->PortNumber );

            printf ( "        ServerCertificateFilename = %s\n", Tester->ServerCertificateFilename         );
            printf ( "     ServerCertificateKeyFilename = %s\n", Tester->ServerCertificateKeyFilename      );
            printf ( "CertificateAuthorityChainFilename = %s\n", Tester->CertificateAuthorityChainFilename );

            printf ( "              TesterDebugFileName = %s\n", TesterDebugFileName          );
            printf ( "      ComponentStatisticsFileName = %s\n", ComponentStatisticsFileName  );
            printf ( "     RecordedMeasurementsFileName = %s\n", RecordedMeasurementsFileName );
        }
    }
    else
    {
        printf ( "Tester object not instantiated yet when checking command line!\n" );
    }
}

//*********************************************************************************************************************************

void TestImageCreation ( void )
{
    int i;
    int y;
    int ImageHeight = 1000;
    int ImageWidth  = 2000;
    const char *FontPath  = "C:\\Program Files (x86)\\Graphviz2.38\\share\\fonts\\FreeSans.ttf";
    const char *Text      = "Text";

    pngwriter TestImage ( ImageWidth, ImageHeight, 255, "test.png" );

    for ( i = 1; i < ImageWidth; i++ )
    {
        y = ( ImageHeight / 2 ) + ( ImageHeight / 3) * sin ( ( double ) i*9 / ImageWidth );

        TestImage.plot ( i, y, 0.0, 1.0, 0.0 ); // x, y, r, g, b

        TestImage.plot_text_utf8 ( (char *) FontPath, 40, 200, 200, (double) 0.0, (char *) Text, 60000, 0, 0 );
    }

    TestImage.close ();
}

//*********************************************************************************************************************************

int main ( int   ArgumentCount,
           char *ArgumentList         [],
           char *EnvironmentVariables [] )
{
    static FILE *ComponentStatisticsFile  = NULL;
    static FILE *DebugFile                = NULL;
    static FILE *RecordedMeasurementsFile = NULL;

    printf ( TitleText );

    ProcessCommandLine ( ArgumentCount, ArgumentList, EnvironmentVariables, TRUE );

    if ( ArgumentCount < 2 )
    {
        printf ( HelpText );
    }
    else
    {
        //
        // open the debug file
        //
        DebugFile = OpenDebugFile ();

        if ( DebugFile != NULL )
        {
            fprintf ( DebugFile, "Tester Debug file '%s' created successfully!\n", TesterDebugFileName );

            //
            // open the statistics file
            //
            ComponentStatisticsFile = OpenStatisticsFile ();

            if ( ComponentStatisticsFile != NULL )
            {
                fprintf ( DebugFile,  "Component Statistics file '%s' opened successfully!\n", ComponentStatisticsFileName );

                //
                // open the recorded measurements file
                //
                RecordedMeasurementsFile = OpenRecordedMeasurementsFile ();

                if ( RecordedMeasurementsFile != NULL )
                {
                    fprintf ( DebugFile,  "Recorded Measurements file '%s' opened successfully!\n", RecordedMeasurementsFileName );

                    //
                    // Create a TESTER object instance
                    //
                    Tester = new TLSTESTER ( DebugFile, ComponentStatisticsFile, RecordedMeasurementsFile );

                    if ( Tester != NULL )
                    {
                        fprintf ( DebugFile, "TLSTESTER object created successfully!\n" );

                        // get the command line arguments, if any defined

                        GetTestParameters ( ArgumentCount, ArgumentList, EnvironmentVariables, TRUE );

                        Tester->Configure (); // configure the component with the correct test parameters

#if defined ( _MSC_VER )
                        // enable coloured console output in windows

                        HANDLE ConsoleHandle = GetStdHandle ( STD_OUTPUT_HANDLE );  // Get handle to standard output
                        DWORD  ConsoleMode = 0;

                        GetConsoleMode ( ConsoleHandle, &ConsoleMode );

                        SetConsoleMode ( ConsoleHandle, ConsoleMode | ENABLE_VIRTUAL_TERMINAL_PROCESSING );

                        SetConsoleTextAttribute ( ConsoleHandle, FOREGROUND_RED + FOREGROUND_GREEN + FOREGROUND_BLUE + FOREGROUND_INTENSITY ); //bright white!
#endif
                        OpenConsoleCopyFile ();

                        //
                        // Now run the tests
                        //
                        if ( Tester->Setup ( DateAndTimeString ) )
                        {
                            // test both protocols with libmitls.dll and an internet server

                            if ( Tester->DoClientTests )
                            {
                                if ( Tester->DoTLSTests ) Tester->RunClientTLSTests ( DateAndTimeString );

                                if ( Tester->DoQUICTests ) Tester->RunClientQUICTests ( DateAndTimeString );
                            }

                            // test both protocols with libmitls.dll running in both client and server modes locally

                            if ( Tester->DoServerTests )
                            {
                                if ( Tester->DoTLSTests ) Tester->RunServerTLSTests ( DateAndTimeString );

                                if ( Tester->DoQUICTests ) Tester->RunServerQUICTests ( DateAndTimeString );
                            }

                            // test libmitls.dll in client mode with known local server implementations

                            if ( Tester->DoClientInteroperabilityTests )
                            {
                                if ( Tester->DoTLSTests )
                                {
                                    Tester->RunOpenSSLClientTLSTests ( DateAndTimeString );

                                    Tester->RunBoringClientTLSTests ( DateAndTimeString );

                                    Tester->RunMbedTLSClientTLSTests ( DateAndTimeString );

                                    Tester->RunWolfSSLClientTLSTests ( DateAndTimeString );

                                    Tester->RunFizzClientTLSTests ( DateAndTimeString );
                                }

                                if ( Tester->DoQUICTests )
                                {
                                    Tester->RunOpenSSLClientQUICTests ( DateAndTimeString );

                                    Tester->RunBoringClientQUICTests ( DateAndTimeString );

                                    Tester->RunMbedTLSClientQUICTests ( DateAndTimeString );

                                    Tester->RunWolfSSLClientQUICTests ( DateAndTimeString );

                                    Tester->RunFizzClientQUICTests ( DateAndTimeString );
                                }
                            }

                            // test libmitls.dll in server mode with known local client implementations

                            if ( Tester->DoServerInteroperabilityTests )
                            {
                                if ( Tester->DoTLSTests )
                                {
                                    Tester->RunOpenSSLServerTLSTests ( DateAndTimeString );

                                    Tester->RunBoringServerTLSTests ( DateAndTimeString );

                                    Tester->RunMbedTLSServerTLSTests ( DateAndTimeString );

                                    Tester->RunWolfSSLServerTLSTests ( DateAndTimeString );

                                    Tester->RunFizzServerTLSTests ( DateAndTimeString );
                                }

                                if ( Tester->DoQUICTests )
                                {
                                    Tester->RunOpenSSLServerQUICTests ( DateAndTimeString );

                                    Tester->RunBoringServerQUICTests ( DateAndTimeString );

                                    Tester->RunMbedTLSServerQUICTests ( DateAndTimeString );

                                    Tester->RunWolfSSLServerQUICTests ( DateAndTimeString );

                                    Tester->RunFizzServerQUICTests ( DateAndTimeString );
                                }
                            }

                            Tester->TearDown ();
                        }
                        else
                        {
                            fprintf ( DebugFile, "Tester->Setup() failed!\n" );
                        }

                        delete Tester;

                        CloseConsoleCopyFile ();

                        fprintf ( DebugFile, "TLSTESTER object destroyed!\n" );

                        fprintf ( stderr,  "Finished Testing!" ); // you want this no matter what to tell the user when the tester is finished!
                    }
                    else
                    {
                        fprintf ( DebugFile, "Cannot create TESTER object\n" );
                    }

                    fclose ( RecordedMeasurementsFile );

                    fprintf ( DebugFile, "Recorded Measurements file closed!\n" );
                }
                else
                {
                    fprintf ( DebugFile, "Cannot open recorded measurements file!\n" );
                }

                fclose ( ComponentStatisticsFile );

                fprintf ( DebugFile, "Statistics file closed!\n" );
            }
            else
            {
                fprintf ( DebugFile, "Cannot open statistics file!\n" );
            }

            fprintf ( DebugFile, "Closing Debug file!\n" );

            fclose ( DebugFile );
        }
        else
        {
            printf ( "Cannot create debug file!\n" );
        }
    }

    return ( 0 );
}

//**********************************************************************************************************************************
