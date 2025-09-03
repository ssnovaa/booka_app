buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        // Единственное место, где объявляем версию плагина Google Services
        classpath("com.google.gms:google-services:4.4.2")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// Выносим build/ каталоги модулей во внешний общий build (как в шаблоне Flutter)
val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

// Гарантируем, что :app прооценится раньше остальных (как в шаблоне Flutter)
subprojects {
    project.evaluationDependsOn(":app")
}

// Задача clean
tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

// Подавляем ворнинги компилятора Java о «obsolete options»
subprojects {
    tasks.withType<JavaCompile>().configureEach {
        options.compilerArgs.add("-Xlint:-options")
    }
}
