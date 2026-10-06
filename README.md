# Hammerspace PowerShell Module

The Hammerspace PowerShell module can assist with many cluster administration and reporting tasks, and offers some unique features that the admin CLI does not:

- The tool can be used without using a cluster shell; all commands flow through the cluster API.
- Much more information is returned and can be configured than in the admin CLI.
- You can use for loops to change settings on multiple items at once, removing the need to use serviceadmin for these changes.
- You have access to the entire API, or at least what I was able to extract from Swagger.

This module is a work in progress and is currently subject to the following issues:

- Lack of consistent documentation of individual commands and command options.
- Not all commands have been tested.
- Some commands are repeated, likely an oddity of our API.

## What is this module?

The module was created by exporting the entire API set from the cluster swagger interface, then using Claude to generate the module and iterate on the command names to make them a little cleaner than the API names themselves.

Unlike the admin CLI, this module includes all API calls available via the Swagger interface. That means it can do far more than the admin CLI, though it lacks explanations of what those commands do. Were we to release this to customers, I would suggest removing some of these more obscure and potentially dangerous commands.

## How do I use this module?

Download the following two files and place them in a folder. You will need the full path to this folder to import the PowerShell module.


Execute the following commands to store your credentials, import the module, and connect to a Hammerspace cluster:

`$cred = Get-Credential`

`PowerShell credential request`

`Enter your credentials.`

`User: admin`

`Password for user admin: ************`

`import-module /Users/Thor/Desktop/Hammerspace/Hammerspace.psm1`

`Connect-HammerspaceSession -HsHost 10.200.10.160 -Credential $cred -SkipCertificateCheck`

`Connected to Hammerspace at 10.200.10.160:8443`

You are now connected to a cluster and can issue PowerShell commands against it.

## PowerShell Command Syntax

To avoid clashing with the default PowerShell commands, all commands follow the following format. 

\<action\>-**hs**\<command\>

The **hs **is used to identify those that target your Hammerspace cluster.

A full list of commands is available here: . This is merely a list, no explanations as of yet. However, I tried to make the commands easier to identify by naming them similarly to the admin CLI commands.

## How is this any different from the admin CLI again?

Example 1: More information returned (partial output):

Example 2: More commands (these are just gets, see the above text file for the full list): 

## Why might someone want this?

There are a few obvious reasons why employees and customers alike may find this module useful.

- Obtain far more cluster configuration data than is available in the admin CLI, or even a support bundle.
- Perform CLI tasks without needing to use the cluster console or even the GUI.
- Simplifies using the cluster API for orchestration purposes.
- Makes it easier to perform configuration changes across multiple items (shares, volumes, volume groups, etc.)

## Feedback?

Contact me, or once this is on GitHub, feel free to improve it. Once it is available there, I will remove the download links from this page.
