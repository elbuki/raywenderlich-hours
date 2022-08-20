#  raywenderlich-hours

This is a script I made to analyze how many hours it would take to watch all the courses from the iOS path in the Ray Wenderlich [website](http://raywenderlich.com/). All the data comes from the website itself in real time using concurrency for each course category. And then it extracts the data using a HTML parser.

The script uses the following Swift libraries:
* SwiftSoup
* URLSession
* TaskGroup
