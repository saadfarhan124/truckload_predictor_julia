(pwd() != @__DIR__) && cd(@__DIR__) # allow starting app from bin/ dir

using DockerTest
const UserApp = DockerTest
DockerTest.main()
