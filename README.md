# Pdocker v2.1.0

Pdocker is a simple terminal UI to maintain and manage personal projects in Docker.

## Getting Started

These instructions will get you a copy of the project up and running on your local machine.

### Operation Systems

* Mac OS

### Prerequisites

* Docker
* Bash

### Installing

A step by step series of examples that tell you how to get a pdocker running

Step 1: Clone the repo.
```
git clone https://github.com/g31s/pdocker.git
```
Step 2: Go to project directory and change permissions for build.sh && pdocker.sh
```
chmod +x build.sh
```
Step 3: Run build.sh
```
./build.sh
```
Step 4: Type pdocker in terminal
```
pdocker
```
Note: if pdocker dosn't work. Start your terminal again or source bash_profile

### Usage

#### Creating new containers
```
pdocker n
or
pdocker new
```
#### Start existing Container
```
pdocker
```
And select container ID/Name
### Open Port for existing Container
```
pdocker op
or
pdocker open_port
```
### Delete Container
```
pdocker d
or
pdocker delete
```
### Delete All Container
```
pdocker da
or
pdocker delete_all
```
### Help
```
pdocker h
or
pdocker help
```

## Authors

* **g31s** - *Initial work* - [g31s](https://github.com/g31s)

See also the list of [contributors](https://github.com/g31s/pdocker/contributors) who participated in this project.

## License

This project is licensed under the MIT License - see the [LICENSE.md](LICENSE.md) file for details