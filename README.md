# pi

![progress](https://progress-bar.dev/0/)

Tool used to create the Ubuntu Kylin images for Raspberry Pi.

## Guiding principles

* Cross-architectures build via docker & qemu
* Splitting the software installation order by dependency and importance
* Using git for version control of non-volatile files
* Encapsulate the interface by architecture for different versions of Raspberry Pi

## Dependencies

__pi__ runs on any Linux distribution that has the **docker** service installed. Check that docker is running properly before running the build service.
