---
title: SpringBoot启动流程
categories:
  - SpringBoot
tags:
  - springboot
  - 源码分析
---


# SpringBoot 启动流程

<br>

- [SpringBoot 启动流程](#springboot-启动流程)
  - [初始化](#初始化)
  - [run](#run)

<br>

启动从`SpringApplication.run(MyServiceApplication.class, args);`开始，然后到SpringApplication的静态run方法中new 一个 `SpringApplication`对象并调用它的run方法

```java
/* SpringApplication */
public static ConfigurableApplicationContext run(Class<?>[] primarySources,
        String[] args) {
    return new SpringApplication(primarySources).run(args);
}

```

启动流程可以主要分为两大部分，一部分是初始化 就是创建`SpringApplication`对象，一部分是run。

首先分析初始化的过程.

<br>

-------------

## 初始化

```java
// resourceLoader = null, primarySource 就是一个class数组，里面存了我们的MyServiceApplication.class
public SpringApplication(ResourceLoader resourceLoader, Class<?>... primarySources) {
    this.resourceLoader = resourceLoader;
    Assert.notNull(primarySources, "PrimarySources must not be null");
    //将我们启动类（其实是注解类，将来用来扫面该类注解，解析该类）类放在 primarySource 中保存起来
    this.primarySources = new LinkedHashSet<>(Arrays.asList(primarySources));
    // 推断WebApplicationType 这里返回SERVLET
    this.webApplicationType = WebApplicationType.deduceFromClasspath();
    // 初始化 并设置 initializers
    setInitializers((Collection) getSpringFactoriesInstances(
            ApplicationContextInitializer.class));
    // 初始化 并设置 listeners
    setListeners((Collection) getSpringFactoriesInstances(ApplicationListener.class));
    // 推断 主应用程序的类 也就是我们的main 函数所在的类
    this.mainApplicationClass = deduceMainApplicationClass();
}

```

<br>

**推断WebApplicationType**

这里返回的是`SERVLET`，共有以下几种：

- `NONE` The application should not run as a web application and should not start an embedded web server.
- `SERVLET` The application should run as a servlet-based web application and should start an embedded servlet web server.
- `REACTIVE` The application should run as a reactive web application and should start an embedded reactive web server.

在我们初始化完成之后，调用run方法之前，也可以去手动指定该type：`setWebApplicationType(webApplicationType)`

<br>

**初始化 并设置 initializers**

根据`META-INF/spring.factories`中存储的映射关系，找到对应类型`org.springframework.context.ApplicationContextInitializer`的类的名字数组，完成初始化并返回。

```java
/* SpringApplication */
private <T> Collection<T> getSpringFactoriesInstances(Class<T> type,
        Class<?>[] parameterTypes, Object... args) {
    ClassLoader classLoader = getClassLoader();
    // Use names and ensure unique to protect against duplicates
    // 获取 type 对应的类名数组
    Set<String> names = new LinkedHashSet<>(
            SpringFactoriesLoader.loadFactoryNames(type, classLoader));
    // 实例化
    List<T> instances = createSpringFactoriesInstances(type, parameterTypes,
            classLoader, args, names);
    AnnotationAwareOrderComparator.sort(instances);
    return instances;
}

/* 
 SpringFactoriesLoader
 该类就是专门加载 所有 META-INF/spring.factories 配置文件，并将结果缓存起来，并提供了根据类的类型返回类名数组的方法
 */

public static List<String> loadFactoryNames(Class<?> factoryClass, @Nullable ClassLoader classLoader) {
    String factoryClassName = factoryClass.getName();
    // 获取该classloader对应的所有资源中的属性对，并获取 该factoryClass对应的类名组
    return loadSpringFactories(classLoader).getOrDefault(factoryClassName, Collections.emptyList());
}

/**
 * 根据classloader 返回该classloader加载的所有资源中 属性对
 */
private static Map<String, List<String>> loadSpringFactories(@Nullable ClassLoader classLoader) {
    // cache 是用来缓存 扫面出来的结果的
    // 如果cache 中没找到，也就是该classloader的第一次扫描， 就去扫描
    MultiValueMap<String, String> result = cache.get(classLoader);
    if (result != null) {
        return result;
    }

    try {
        // 获取所有的url
        Enumeration<URL> urls = (classLoader != null ?
                classLoader.getResources(FACTORIES_RESOURCE_LOCATION) :
                ClassLoader.getSystemResources(FACTORIES_RESOURCE_LOCATION));
        result = new LinkedMultiValueMap<>();
        while (urls.hasMoreElements()) {
            URL url = urls.nextElement();
            UrlResource resource = new UrlResource(url);
            Properties properties = PropertiesLoaderUtils.loadProperties(resource);
            for (Map.Entry<?, ?> entry : properties.entrySet()) {
                String factoryClassName = ((String) entry.getKey()).trim();
                for (String factoryName : StringUtils.commaDelimitedListToStringArray((String) entry.getValue())) {
                    result.add(factoryClassName, factoryName.trim());
                }
            }
        }
        cache.put(classLoader, result);
        return result;
    }
    catch (IOException ex) {
        throw new IllegalArgumentException("Unable to load factories from location [" +
                FACTORIES_RESOURCE_LOCATION + "]", ex);
    }
}


```

比如其中的一个 `META-INFO/spring.factories` 如下：`jar:file:/Users/wuyingjie/.m2/repository/org/springframework/boot/spring-boot-autoconfigure/2.1.0.RELEASE/spring-boot-autoconfigure-2.1.0.RELEASE.jar!/META-INF/spring.factories`

![|center](/images/springboot启动流程-1.png)

result 也就是扫描出来的所有key和类名数组如下：

![|center](/images/springboot启动流程-2.png)

`org.springframework.context.ApplicationContextInitializer`对应的类有：

![|center](/images/springboot启动流程-3.png)


<br>

**初始化 并设置 applicationlisteners**

`org.springframework.context.ApplicationListener` 对应的类有：

![|center](/images/springboot启动流程-4.png)

<br>

**推断 主应用程序的类 也就是我们的main 函数所在的类**

就是根据栈的调用信息，获取main函数所在的栈帧，最后得到类信息

```java
private Class<?> deduceMainApplicationClass() {
    try {
        StackTraceElement[] stackTrace = new RuntimeException().getStackTrace();
        for (StackTraceElement stackTraceElement : stackTrace) {
            if ("main".equals(stackTraceElement.getMethodName())) {
                return Class.forName(stackTraceElement.getClassName());
            }
        }
    }
    catch (ClassNotFoundException ex) {
        // Swallow and continue
    }
    return null;
}
```

<br>

SpringApplication的初始化到这里也就结束了。

其实也就是在为WebApplicationContext的初始化 做一些准备工作。

<br>

-------------

## run

run方法代码如下，而且结构非常清晰。

```java
public ConfigurableApplicationContext run(String... args) {
    StopWatch stopWatch = new StopWatch();
    stopWatch.start();
    ConfigurableApplicationContext context = null;
    Collection<SpringBootExceptionReporter> exceptionReporters = new ArrayList<>();
    configureHeadlessProperty();
    // 获取 刚刚初始化时 得到的所有listeners
    SpringApplicationRunListeners listeners = getRunListeners(args);
    // 发送 ApplicationStartingEvent 事件
    listeners.starting();
    try {
        // 包装 main方法中的传递的参数 
        ApplicationArguments applicationArguments = new DefaultApplicationArguments(
                args);
        // 初始化 环境，并发送 ApplicationEnvironmentPreparedEvent 事件
        ConfigurableEnvironment environment = prepareEnvironment(listeners,
                applicationArguments);
        configureIgnoreBeanInfo(environment);
        // 打印 banner
        Banner printedBanner = printBanner(environment);
        // 根据不同的 WebApplicationType（我们的是SERVLET）创建不同的ApplicationContext对象实例
        context = createApplicationContext();
        // 使用 SpringFactoriesLoader 获取 org.springframework.boot.SpringBootExceptionReporter 对应的 exceptionReporters
        exceptionReporters = getSpringFactoriesInstances(
                SpringBootExceptionReporter.class,
                new Class[] { ConfigurableApplicationContext.class }, context);
        /**
         * 1. 准备一下context的环境
         * 2. 调用上文所有 ApplicationContextInitializer.initialize 方法，趁 context 还没有 refresh
         * 3. 发送 ApplicationContextInitializedEvent 事件
         * 4. load allResource=resources+primaryResources 这里主要就是 加载主类 MyServiceAppliction
         * 5. 做了一些 contextLoaded 的工作，主要是 发送 ApplicationPreparedEvent 事件
         */
        prepareContext(context, environment, listeners, applicationArguments,
                printedBanner);
        // 调用 ApplicationContext 的 refresh 方法
        refreshContext(context);
        // 调用 afterRefresh 但其实是个空方法，啥都没干
        afterRefresh(context, applicationArguments);
        stopWatch.stop();
        if (this.logStartupInfo) {
            new StartupInfoLogger(this.mainApplicationClass)
                    .logStarted(getApplicationLog(), stopWatch);
        }
        // 发送 ApplicationStartedEvent 事件
        listeners.started(context);
        callRunners(context, applicationArguments);
    }
    catch (Throwable ex) {
        handleRunFailure(context, ex, exceptionReporters, listeners);
        throw new IllegalStateException(ex);
    }

    try {
        // 发送 ApplicationReadyEvent 事件
        listeners.running(context);
    }
    catch (Throwable ex) {
        handleRunFailure(context, ex, exceptionReporters, null);
        throw new IllegalStateException(ex);
    }
    return context;
}

```

整个启动流程 就完成了。

<br>

----------


那么下面就仔细的分析每一步具体做了什么。

<br>

**获取listeners 并通知listeners事件**

获取`SpringApplicationRunListeners`的方法如下：

```java
private SpringApplicationRunListeners getRunListeners(String[] args) {
    Class<?>[] types = new Class<?>[] { SpringApplication.class, String[].class };
    return new SpringApplicationRunListeners(logger, getSpringFactoriesInstances(
            SpringApplicationRunListener.class, types, this, args));
}
```

还是使用`SpringFactoriesLoader`类从各个 `spring.factories`配置文件中获取。得到的是`SpringApplicationRunListener`所有配置在`spring.factories`中的子类的数组，这里该数组只有一个元素`org.springframework.boot.context.event.EventPublishingRunListener`

首先，我们看下`SpringApplicationRunListener`，该接口提供了Application运行期各个事件的回调，也就是上面所有的事件其实都是这里发的


```java
package org.springframework.boot;

import org.springframework.context.ApplicationContext;
import org.springframework.context.ConfigurableApplicationContext;
import org.springframework.core.env.ConfigurableEnvironment;
import org.springframework.core.io.support.SpringFactoriesLoader;

/**
 * Listener for the {@link SpringApplication} {@code run} method.
 * {@link SpringApplicationRunListener}s are loaded via the {@link SpringFactoriesLoader}
 * and should declare a public constructor that accepts a {@link SpringApplication}
 * instance and a {@code String[]} of arguments. A new
 * {@link SpringApplicationRunListener} instance will be created for each run.
 *
 * @author Phillip Webb
 * @author Dave Syer
 * @author Andy Wilkinson
 */
public interface SpringApplicationRunListener {

	/**
	 * Called immediately when the run method has first started. Can be used for very
	 * early initialization.
	 */
	void starting();

	/**
	 * Called once the environment has been prepared, but before the
	 * {@link ApplicationContext} has been created.
	 * @param environment the environment
	 */
	void environmentPrepared(ConfigurableEnvironment environment);

	/**
	 * Called once the {@link ApplicationContext} has been created and prepared, but
	 * before sources have been loaded.
	 * @param context the application context
	 */
	void contextPrepared(ConfigurableApplicationContext context);

	/**
	 * Called once the application context has been loaded but before it has been
	 * refreshed.
	 * @param context the application context
	 */
	void contextLoaded(ConfigurableApplicationContext context);

	/**
	 * The context has been refreshed and the application has started but
	 * {@link CommandLineRunner CommandLineRunners} and {@link ApplicationRunner
	 * ApplicationRunners} have not been called.
	 * @param context the application context.
	 * @since 2.0.0
	 */
	void started(ConfigurableApplicationContext context);

	/**
	 * Called immediately before the run method finishes, when the application context has
	 * been refreshed and all {@link CommandLineRunner CommandLineRunners} and
	 * {@link ApplicationRunner ApplicationRunners} have been called.
	 * @param context the application context.
	 * @since 2.0.0
	 */
	void running(ConfigurableApplicationContext context);

	/**
	 * Called when a failure occurs when running the application.
	 * @param context the application context or {@code null} if a failure occurred before
	 * the context was created
	 * @param exception the failure
	 * @since 2.0.0
	 */
	void failed(ConfigurableApplicationContext context, Throwable exception);

}

```

比如说，我们看看`listeners.starting();`方法

```java
// SpringApplicationRunListeners
public void starting() {
    for (SpringApplicationRunListener listener : this.listeners) {
        // 这里就像上面说的 listeners 只有 EventPublishingRunListener 一个对象
        listener.starting();
    }
}

// 我们看EventPublishingRunListener 的starting 方法
// EventPublishingRunListener
@Override
public void starting() {
    // 调用初始化广播器 将 事件 ApplicationStartingEvent 广播到所有 listeners
    this.initialMulticaster.multicastEvent(
            new ApplicationStartingEvent(this.application, this.args));
}

// 那么我们再看一下 这个 初始化广播器 initialMulticaster 到底是什么，并广播向了哪些listeners
// EventPublishingRunListener 的构造方法
public EventPublishingRunListener(SpringApplication application, String[] args) {
    this.application = application;
    this.args = args;
    // new 一个新的 SimpleApplicationEventMulticaster
    this.initialMulticaster = new SimpleApplicationEventMulticaster();
    // 并将ApplicationContext中所有的listeners 放到 该 广播器中
    // 这些listeners 就是从 spring.factories中加载的 所有 ApplicationListener.class的子类
    for (ApplicationListener<?> listener : application.getListeners()) {
        this.initialMulticaster.addApplicationListener(listener);
    }
}

```

广播逻辑，大致就是在所有的listeners中根据event找到合适的能处理该event的listeners，并调用该listener的onApplicationEvent方法

具体的广播逻辑实现方式就不分析了，可以看我的另一篇介绍**`springboot 事件机制`**的文章，

所以，如果我们想要监听SpringApplication运行期间的各种事件，我们就可以实现`SpringApplicationRunListener`，并仔细看接口的注释。

这里主要涉及到三个类：

- `SpringApplicationRunListeners` 类，包含了所有实现了`SpringApplicationRunListener`接口并通过`spring.factories`注册的类。
- `SpringApplicationRunListener` 接口，定义监听`SpringApplication`运行的回调接口
- `EventPublishingRunListener` 类，实现了`SpringApplicationRunListener`接口，是通过`SpringFactoriesLoader`加载的唯一实现类。

> 另外，这里的`SpringApplicationRunListeners`中的`SimpleApplicationEventMulticaster`只负责SpringApplication启动过程中的事件发送，也只发送给通过`SpringFactoriesLoader`加载并放在它里面的listeners。我们写的自己的listeners和这些listeners都放在`ApplicationContext`中的listeners，并且由`ApplicationContext`中的`SimpleApplicationEventMulticaster`负责通知（他俩并不是同一个）。

<br>

**创建Environment 和 context**

创建`ConfigurableEnvironment`和`ApplicationContext` 都会根据之前得到的`WebApplicationType`。

```java
protected ConfigurableApplicationContext createApplicationContext() {
    Class<?> contextClass = this.applicationContextClass;
    if (contextClass == null) {
        try {
            switch (this.webApplicationType) {
            case SERVLET:
                // AnnotationConfigServletWebServerApplicationContext
                contextClass = Class.forName(DEFAULT_SERVLET_WEB_CONTEXT_CLASS); 
                break;
            case REACTIVE:
                // AnnotationConfigReactiveWebServerApplicationContext
                contextClass = Class.forName(DEFAULT_REACTIVE_WEB_CONTEXT_CLASS);
                break;
            default:
                // AnnotationConfigApplicationContext
                contextClass = Class.forName(DEFAULT_CONTEXT_CLASS);
            }
        }
        catch (ClassNotFoundException ex) {
            throw new IllegalStateException(
                    "Unable create a default ApplicationContext, "
                            + "please specify an ApplicationContextClass",
                    ex);
        }
    }
    return (ConfigurableApplicationContext) BeanUtils.instantiateClass(contextClass);
}
```

<br>

**prepareContext**

```java
private void prepareContext(ConfigurableApplicationContext context,
        ConfigurableEnvironment environment, SpringApplicationRunListeners listeners,
        ApplicationArguments applicationArguments, Banner printedBanner) {
    context.setEnvironment(environment);
    // 注入基本的类 如，ConversionService
    postProcessApplicationContext(context);
    // 调用各个由 SpringFactoriesLoader 加载的 ApplicationContextInitializer 的 initialize方法
    applyInitializers(context);
    // 发布ApplicationContextInitializedEvent 事件
    listeners.contextPrepared(context);
    if (this.logStartupInfo) {
        logStartupInfo(context.getParent() == null);
        logStartupProfileInfo(context);
    }
    // Add boot specific singleton beans
    ConfigurableListableBeanFactory beanFactory = context.getBeanFactory();
    beanFactory.registerSingleton("springApplicationArguments", applicationArguments);
    if (printedBanner != null) {
        beanFactory.registerSingleton("springBootBanner", printedBanner);
    }
    if (beanFactory instanceof DefaultListableBeanFactory) {
        ((DefaultListableBeanFactory) beanFactory)
                .setAllowBeanDefinitionOverriding(this.allowBeanDefinitionOverriding);
    }
    // Load the sources
    Set<Object> sources = getAllSources();
    Assert.notEmpty(sources, "Sources must not be empty");
    // 这里只加载了 我们的主类 MyServiceApplication
    load(context, sources.toArray(new Object[0]));
    //1. 如果这些listeners 实现了 ApplicationContextAware 接口，则将ApplicationContext set进去，因为这时候ApplicationContext已经准备好了，而且 这些已经实例化过了，之后也不会收到通知了。
    //2. 发送 ApplicationPreparedEvent 事件
    listeners.contextLoaded(context);
}
```

<br>

**refresh**

这里还需要着重说一下refresh方法。

上面的load方法只加载了根类 `MyServiceApplication`，而该类下的所有有注解的并没有加载，实际的加载是在refresh的过程中实现的。
```java
// AbstractApplicationContext
public void refresh() throws BeansException, IllegalStateException {
    synchronized (this.startupShutdownMonitor) {
        // Prepare this context for refreshing.
        prepareRefresh();
        ...
        invokeBeanFactoryPostProcessors(beanFactory);
        ...
    }
}

// 最后委托给了 PostProcessorRegistrationDelegate 
public static void invokeBeanFactoryPostProcessors(
    ConfigurableListableBeanFactory beanFactory, List<BeanFactoryPostProcessor> beanFactoryPostProcessors) {

    // 首先，需要明白，BeanFactoryPostProcessor 有两个来源，一个是 传进来的，另外一个是 从BeanFactory中拿到的。

    // 代码就省了 写下大致逻辑，也是比较简单的

    if (beanFactory instanceof BeanDefinitionRegistry) {
        // 如果是一个可以注册的BeanFactory，
        
        /*
         1. 从参数中的 beanFactoryPostProcessors 中找实现 BeanDefinitionRegistryPostProcessor接口的 并调用该方法
         2. 调用BeanFactory中的BeanDefinitionRegistryPostProcessor接口
         3. 调用 BeanDefinitionRegistryPostProcessor接口的 BeanFactoryPostProcessors 的接口方法
         4. 调用 参数中的 BeanFactoryPostProcessors 接口的方法
        */

    } else {
        // 如果不可以注册bean

        // 调用所有参数的 BeanFactoryPostProcessors 接口方法
    }

    //调用 beanFactory中的 BeanFactoryPostProcessors 接口方法
}
```

而 SpringBoot 自动装配，去解析根类中的注解并注入bean的过程就发生在 `BeanDefinitionRegistryPostProcessor`的调用过程中。

具体实现的类是`ConfigurationClassPostProcessor`。 具体过程还是挺复杂的，之后可以详细分析。

refresh 方法也是非常重要的，但是不是本文的重点，具体可以去百度。

> 这里是主要的`BeanFactoryPostProcessor`的来源，但是还有一些来自 `ApplicationContextInitializer`实现类，在调用回调方法时注入的几个（他这么着急注入是要早点用？可是哪里都没有调用啊。。 可能是一些需要提前获取的bean在getBean方法的时候会回调这些早早就初始化好的`BeanFactoryPostProcessor`）。

> 另外，`BeanPostProcessor`也是有一些需要提前注册好的。还有一些Bean，比如说`spring.factories`中注册的bean，还有回调或者初始化其他类的时候增加的一些BeanDefinition。如在实例化`AnnotationConfigServletWebServerApplicationContext`会创建`AnnotatedBeanDefinitionReader`对象，在实例化该对象的时候，会像BeanFactory中注册Annotion方式的BeanRegistry所必须用到的几个类，比如说`ConfigurationClassPostProcessor`，`AutowiredAnnotationBeanPostProcessor`，`CommonAnnotationBeanPostProcessor`等等吧。


<br>

再之后，除了还是`SpringApplicationRunListeners`的回调，还有一个`callRunners`方法。

<br>

**callRunners**

```java
private void callRunners(ApplicationContext context, ApplicationArguments args) {
    List<Object> runners = new ArrayList<>();
    runners.addAll(context.getBeansOfType(ApplicationRunner.class).values());
    runners.addAll(context.getBeansOfType(CommandLineRunner.class).values());
    AnnotationAwareOrderComparator.sort(runners);
    for (Object runner : new LinkedHashSet<>(runners)) {
        if (runner instanceof ApplicationRunner) {
            callRunner((ApplicationRunner) runner, args);
        }
        if (runner instanceof CommandLineRunner) {
            callRunner((CommandLineRunner) runner, args);
        }
    }
}   
```

主要就是回调以下两个接口，对我们运行时传入的参数 加上自己的处理（如果有需要的话）：
- `ApplicationRunner` 接收由`ApplicationArguments`包装之后的参数
- `CommandLineRunner` 接收原始运行程序传入的参数

例子 网上一百度 就有了。比如说：[CommandLineRunner或者ApplicationRunner接口](https://www.jianshu.com/p/5d4ffe267596)