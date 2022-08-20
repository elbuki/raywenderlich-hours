//
//  main.swift
//  raywenderlich-hours
//
//  Created by Marco Carmona on 8/20/22.
//

import Foundation
import SwiftSoup

enum RequestError: Error {
    case buildingURL
    case requestingWebpage
    case gettingRawHTML
    case parsingDuration
}

struct Course {
    let name: String
    let duration: Int
    let url: URL
}

struct RayWenderlichAnalyzer {
    let baseURL = "https://www.raywenderlich.com"
    let pathsURL = "/ios/paths"
    let pathBlacklist = [
        "/learn",
        "/uikit",
    ]
    let courseBlacklist = [
        "/4418-beginning-git",
        "/4729-command-line-basics",
    ]
    
    public func getHours() async throws {
        var totalMinutes = 0
        
        let pathsResponse = try await requestWebpage(to: pathsURL)
        let parsedPaths = try SwiftSoup.parse(pathsResponse)
        let pageLinks = try pathPageLinks(from: parsedPaths)
        let courses = try await fetchCourseData(from: pageLinks)
        
        for item in courses {
            totalMinutes += item.duration
        }
        
        let (hours, minutes) = formatMinutes(totalMinutes)
        
        print(
            "The total time to watch the Ray Wenderlich iOS path is " +
            "\(hours) hours and \(minutes) minutes."
        )
    }
    
    private func requestWebpage(to path: String) async throws -> String {
        guard let url = URL(string: baseURL + path) else {
            throw RequestError.requestingWebpage
        }

        return try await requestWebpage(to: url)
    }
    
    private func requestWebpage(to url: URL) async throws -> String {
        let (rawData, _) = try await URLSession.shared.data(from: url)
        
        guard let rawHTML = String(data: rawData, encoding: .utf8) else {
            throw RequestError.gettingRawHTML
        }
        
        return rawHTML
    }
    
    private func pathPageLinks(from document: Document) throws -> [URL] {
        var pathLinks: [URL] = []
        var pathElements: Elements
        
        pathElements = try document.select(".c-tutorial-item.c-tutorial-item--learning-path")
        
        for element in pathElements {
            let overlayLink = try element.select("a.c-tutorial-item__overlay")
            let path = try overlayLink.attr("href")
            let urlString = baseURL + path
            let splitted = path.split(separator: "/")
            let lastPathPortion = "/\(splitted.last ?? "")"
            
            if pathBlacklist.contains(lastPathPortion) {
                continue
            }
            
            if let fullURL = URL(string: urlString) {
                pathLinks.append(fullURL)
                continue
            }
            
            throw RequestError.buildingURL
        }
        
        return pathLinks
    }
    
    private func fetchCourseData(from urls: [URL]) async throws -> [Course] {
        let data = try await withThrowingTaskGroup(
            of: [Course].self,
            returning: [Course].self
        ) { taskGroup in

            for url in urls {
                taskGroup.addTask {
                    let learningPathPageHTML = try await requestWebpage(to: url)
                    let parsedCourses = try parseCoursesFromPathPage(using: learningPathPageHTML)

                    return parsedCourses
                }
            }
            
            return try await taskGroup
                .reduce(into: [[Course]]()) { $0.append($1) }
                .flatMap { $0 }

        }
        
        return data
    }
    
    private func parseCoursesFromPathPage(using rawHTML: String) throws -> [Course] {
        let parsedPath = try SwiftSoup.parse(rawHTML)
        let courseWrapperElements = try parsedPath.select(".c-tutorial-item")
        var courses: [Course] = []
        
        for wrapper in courseWrapperElements {
            let titleElement = try wrapper.select(".c-tutorial-item__title")
            let metadataElement = try wrapper.select(".c-tutorial-item__metadata")
            let overlayLinkElement = try wrapper.select("a")
            let path = try overlayLinkElement.attr("href")
            let courseTitle = try titleElement.html()
            let metadataText = try metadataElement.text()
            var courseData: Course
            
            guard let courseURL = URL(string: baseURL + path) else {
                throw RequestError.buildingURL
            }
            
            courseData = Course(
                name: courseTitle,
                duration: try parseCourseDuration(from: metadataText),
                url: courseURL
            )
            
            courses.append(courseData)
        }
        
        return courses
    }
    
    private func parseCourseDuration(from metadata: String) throws -> Int {
        var durationText: String.SubSequence
        var minutes: Int
        var hours = 0
        
        guard let leftIndex = metadata.firstIndex(of: "(") else {
            throw RequestError.parsingDuration
        }
        
        guard let rightIndex = metadata.lastIndex(of: ")") else {
            throw RequestError.parsingDuration
        }
        
        durationText = metadata[leftIndex...rightIndex]

        if durationText.contains("hr") {
            let splitted = durationText.split(separator: ",")
            
            hours = try numbersFromDuration(splitted[0])
            durationText = splitted[1]
        }
        
        minutes = try numbersFromDuration(durationText)
        
        return (hours * 60) + minutes
    }
    
    private func numbersFromDuration(_ duration: String.SubSequence) throws -> Int {
        let durationText = duration.components(separatedBy: CharacterSet.decimalDigits.inverted)
        
        guard let parsed = Int(durationText.joined()) else {
            throw RequestError.parsingDuration
        }
        
        return parsed
    }
    
    private func formatMinutes(_ minutes: Int) -> (hours: Int, minutes: Int) {
        return (minutes / 60, minutes % 60)
    }
}

@main
struct Analyzer {
    static func main() async throws {
        let analyzer = RayWenderlichAnalyzer()
        
        do {
            try await analyzer.getHours()
        } catch {
            fatalError("Could not get the path duration: \(error.localizedDescription)")
        }
    }
}
