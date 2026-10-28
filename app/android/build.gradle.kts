allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// Some plugins (e.g. file_picker) still pin an older compileSdk than the newer
// transitive AndroidX/Flutter libraries now require. Force every Android module
// to compile against SDK 36; compiling against a newer SDK is backward
// compatible and minSdk still governs which devices can install the app.
// The block above force-evaluates :app, so guard against configuring an
// already-evaluated project (afterEvaluate would throw).
subprojects {
    if (project.state.executed) {
        (extensions.findByName("android") as? com.android.build.gradle.BaseExtension)
            ?.compileSdkVersion(36)
    } else {
        afterEvaluate {
            (extensions.findByName("android") as? com.android.build.gradle.BaseExtension)
                ?.compileSdkVersion(36)
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
