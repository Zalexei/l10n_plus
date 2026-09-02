# Changelog

## 0.1.0

First release. A `build_runner` adapter over the same generator API the CLI
uses; both produce byte-identical output.

* Reads every translation file through `BuildStep`, so `build_runner` treats
  them as tracked inputs and rebuilds when one changes.
* Finds translations in subdirectories, for projects that split a locale
  across several files.
* Outputs are declared in `build.yaml`, which is `build_runner`'s rule rather
  than something an adapter can hide; a file the generator wanted to write but
  could not is reported by name with the block to paste.
