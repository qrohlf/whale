# Whale
*A distributed parallel rendering system for my spring 2014 Advanced Graphics class*

## What it is
Whale is a control system for performing distributed and parallel rendering via SSH in the Lewis & Clark Simpson linux lab. It can perform a rendering job in three minutes that would take over an hour for a single machine to do. It's based off some code I wrote for a different project that involved paralell SSH.

## What it isn't
Pretty. Whale is held together with SSH, duct tape, and wishful thinking. It works, but the code organization, error handling, and terminal output are all somewhat "unique".

## What it does
Whale is designed to perform the following tasks

1. Upload, install, and compile the rendering code on all target machines.
2. Split a rendering job into blocks and assign each block of work to a target machine.
3. Render all of the frames from the block in parallel on the target machine.
4. Transfer all of the rendered frames back to the control machine in parallel via SCP.