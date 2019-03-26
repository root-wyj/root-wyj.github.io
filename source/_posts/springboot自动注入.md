---
title: SpringBoot-AutoConfiguration 自动装配
categories:
  - SpringBoot
tags:
  - springboot
  - 源码分析
  - 自动装配
  - AutoConfiguration
---


# SpringBoot-AutoConfiguration 自动装配

- [SpringBoot-AutoConfiguration 自动装配](#springboot-autoconfiguration-自动装配)
  - [`ConfigurationClassPostProcessor`的由来](#configurationclasspostprocessor的由来)
  - [`ConfigurationClassPostProcessor`源码分析](#configurationclasspostprocessor源码分析)
    - [parse](#parse)
    - [`@Import`注解的解析](#import注解的解析)
    - [流程总结](#流程总结)
  - [自动装配之条件装配](#自动装配之条件装配)
    - [Condition](#condition)
    - [spring-autoconfigure-metadata.properties](#spring-autoconfigure-metadataproperties)



大家都知道，SpringBoot自动装配的主要角色就是`ConfigurationClassPostProcessor`，在分析它之前，先看看它是怎么被注入和被调用的。

--------

<br>

## `ConfigurationClassPostProcessor`的由来

在`SpringApplication.run`方法的`context = createApplicationContext();`中，可以看到拿到的类名是`DEFAULT_SERVLET_WEB_CONTEXT_CLASS)=org.springframework.boot.web.servlet.context.AnnotationConfigServletWebServerApplicationContext`，然后创建了该类的对象

```java
// AnnotationServletContext 构造方法
public AnnotationConfigServletWebServerApplicationContext() {
    this.reader = new AnnotatedBeanDefinitionReader(this);
    this.scanner = new ClassPathBeanDefinitionScanner(this);
}
```

创建的Context中包含了**`Annotated`BeanDefinition`Reader`**和**`ClassPath`BeanDefinition`Scanner`**。

```java
// AnnotatedReader 构造方法
public AnnotatedBeanDefinitionReader(BeanDefinitionRegistry registry, Environment environment) {
    Assert.notNull(registry, "BeanDefinitionRegistry must not be null");
    Assert.notNull(environment, "Environment must not be null");
    this.registry = registry;
    this.conditionEvaluator = new ConditionEvaluator(registry, environment, null);
    AnnotationConfigUtils.registerAnnotationConfigProcessors(this.registry);
}
```

该`Reader`干了解析`Annotation`非常重要的两件事，一个是创建`ConditionEvaluator`，主要是用来解析和`@Conditional`相关的(Internal class used to evaluate {@link Conditional} annotations.)；另外一个就是注册所有和Annotation相关的`PostProcessor`。

```java
// AnnotationConfigUtils.registerAnnotationConfigProcessors
/**
 * Register all relevant annotation post processors in the given registry.
 */
public static Set<BeanDefinitionHolder> registerAnnotationConfigProcessors(
        BeanDefinitionRegistry registry, @Nullable Object source) {

    DefaultListableBeanFactory beanFactory = unwrapDefaultListableBeanFactory(registry);
    if (beanFactory != null) {
        // 能够支持 @Order 注解，来比较优先级
        if (!(beanFactory.getDependencyComparator() instanceof AnnotationAwareOrderComparator)) {
            beanFactory.setDependencyComparator(AnnotationAwareOrderComparator.INSTANCE);
        }
        if (!(beanFactory.getAutowireCandidateResolver() instanceof ContextAnnotationAutowireCandidateResolver)) {
            beanFactory.setAutowireCandidateResolver(new ContextAnnotationAutowireCandidateResolver());
        }
    }

    Set<BeanDefinitionHolder> beanDefs = new LinkedHashSet<>(8);

    // 注入解析Annotation 非常重要的 ConfigurationClassPostProcessor
    if (!registry.containsBeanDefinition(CONFIGURATION_ANNOTATION_PROCESSOR_BEAN_NAME)) {
        RootBeanDefinition def = new RootBeanDefinition(ConfigurationClassPostProcessor.class);
        def.setSource(source);
        beanDefs.add(registerPostProcessor(registry, def, CONFIGURATION_ANNOTATION_PROCESSOR_BEAN_NAME));
    }

    // 注入 实现 @Autowire (好像还有@Value, @Inject) 注解的赋值
    if (!registry.containsBeanDefinition(AUTOWIRED_ANNOTATION_PROCESSOR_BEAN_NAME)) {
        RootBeanDefinition def = new RootBeanDefinition(AutowiredAnnotationBeanPostProcessor.class);
        def.setSource(source);
        beanDefs.add(registerPostProcessor(registry, def, AUTOWIRED_ANNOTATION_PROCESSOR_BEAN_NAME));
    }

    // Check for JSR-250 support, and if present add the CommonAnnotationBeanPostProcessor.
    // 注入 实现 @PostConstruct 和 @PreDestroy @Resource注解的PostProcessor
    if (jsr250Present && !registry.containsBeanDefinition(COMMON_ANNOTATION_PROCESSOR_BEAN_NAME)) {
        RootBeanDefinition def = new RootBeanDefinition(CommonAnnotationBeanPostProcessor.class);
        def.setSource(source);
        beanDefs.add(registerPostProcessor(registry, def, COMMON_ANNOTATION_PROCESSOR_BEAN_NAME));
    }

    // Check for JPA support, and if present add the PersistenceAnnotationBeanPostProcessor.
    if (jpaPresent && !registry.containsBeanDefinition(PERSISTENCE_ANNOTATION_PROCESSOR_BEAN_NAME)) {
        RootBeanDefinition def = new RootBeanDefinition();
        try {
            def.setBeanClass(ClassUtils.forName(PERSISTENCE_ANNOTATION_PROCESSOR_CLASS_NAME,
                    AnnotationConfigUtils.class.getClassLoader()));
        }
        catch (ClassNotFoundException ex) {
            throw new IllegalStateException(
                    "Cannot load optional framework class: " + PERSISTENCE_ANNOTATION_PROCESSOR_CLASS_NAME, ex);
        }
        def.setSource(source);
        beanDefs.add(registerPostProcessor(registry, def, PERSISTENCE_ANNOTATION_PROCESSOR_BEAN_NAME));
    }

    // 下面两个是实现了 使用@EventListener 类似的注解 实现Listener的注册
    if (!registry.containsBeanDefinition(EVENT_LISTENER_PROCESSOR_BEAN_NAME)) {
        RootBeanDefinition def = new RootBeanDefinition(EventListenerMethodProcessor.class);
        def.setSource(source);
        beanDefs.add(registerPostProcessor(registry, def, EVENT_LISTENER_PROCESSOR_BEAN_NAME));
    }

    if (!registry.containsBeanDefinition(EVENT_LISTENER_FACTORY_BEAN_NAME)) {
        RootBeanDefinition def = new RootBeanDefinition(DefaultEventListenerFactory.class);
        def.setSource(source);
        beanDefs.add(registerPostProcessor(registry, def, EVENT_LISTENER_FACTORY_BEAN_NAME));
    }

    return beanDefs;
}

```

当运行完`prepareEnvrionment`方法之后，BeanFactory中装载了主函数所在的类，此时所有的bean就是 **为Annotation准备提前注入的Bean和主运行程序Bean**。

至此，`Annotation`相关的`PostProcessor`已经准备好了，那么spring是怎么完成自动装配的呢？

-------

<br>

## `ConfigurationClassPostProcessor`源码分析

在调用`AbstractApplicationContext.refresh`的时候，会调用`BeanDefinitionRegistryPostProcessor`。所以此时就会调用`ConfigurationClassPostProcessor.postProcessBeanDefinitionRegistry`:

```java
public void postProcessBeanDefinitionRegistry(BeanDefinitionRegistry registry) {
    // 防止重复调用
    int registryId = System.identityHashCode(registry);
    if (this.registriesPostProcessed.contains(registryId)) {
        throw new IllegalStateException(
                "postProcessBeanDefinitionRegistry already called on this post-processor against " + registry);
    }
    if (this.factoriesPostProcessed.contains(registryId)) {
        throw new IllegalStateException(
                "postProcessBeanFactory already called on this post-processor against " + registry);
    }
    this.registriesPostProcessed.add(registryId);

    processConfigBeanDefinitions(registry);
}

/**
    * Build and validate a configuration model based on the registry of
    * {@link Configuration} classes.
    */
public void processConfigBeanDefinitions(BeanDefinitionRegistry registry) {
    List<BeanDefinitionHolder> configCandidates = new ArrayList<>();
    String[] candidateNames = registry.getBeanDefinitionNames();

    // 把所有被@Configuration注解的类 筛选出来
    for (String beanName : candidateNames) {
        BeanDefinition beanDef = registry.getBeanDefinition(beanName);
        if (ConfigurationClassUtils.isFullConfigurationClass(beanDef) ||
                ConfigurationClassUtils.isLiteConfigurationClass(beanDef)) {
            if (logger.isDebugEnabled()) {
                logger.debug("Bean definition has already been processed as a configuration class: " + beanDef);
            }
        }
        else if (ConfigurationClassUtils.checkConfigurationClassCandidate(beanDef, this.metadataReaderFactory)) {
            configCandidates.add(new BeanDefinitionHolder(beanDef, beanName));
        }
    }

    // Return immediately if no @Configuration classes were found
    // 没找到 就直接返回
    if (configCandidates.isEmpty()) {
        return;
    }

    // Sort by previously determined @Order value, if applicable
    configCandidates.sort((bd1, bd2) -> {
        int i1 = ConfigurationClassUtils.getOrder(bd1.getBeanDefinition());
        int i2 = ConfigurationClassUtils.getOrder(bd2.getBeanDefinition());
        return Integer.compare(i1, i2);
    });

    // Detect any custom bean name generation strategy supplied through the enclosing application context
    // 如果有 BeanNameGenerator(用来生成Bean name的bean) 的话，拿过来用(实际上，现在还没有) 
    SingletonBeanRegistry sbr = null;
    if (registry instanceof SingletonBeanRegistry) {
        sbr = (SingletonBeanRegistry) registry;
        if (!this.localBeanNameGeneratorSet) {
            BeanNameGenerator generator = (BeanNameGenerator) sbr.getSingleton(CONFIGURATION_BEAN_NAME_GENERATOR);
            if (generator != null) {
                this.componentScanBeanNameGenerator = generator;
                this.importBeanNameGenerator = generator;
            }
        }
    }

    if (this.environment == null) {
        this.environment = new StandardEnvironment();
    }

    // Parse each @Configuration class
    ConfigurationClassParser parser = new ConfigurationClassParser(
            this.metadataReaderFactory, this.problemReporter, this.environment,
            this.resourceLoader, this.componentScanBeanNameGenerator, registry);

    Set<BeanDefinitionHolder> candidates = new LinkedHashSet<>(configCandidates);
    Set<ConfigurationClass> alreadyParsed = new HashSet<>(configCandidates.size());
    do {
        // parse
        parser.parse(candidates);
        parser.validate();

        Set<ConfigurationClass> configClasses = new LinkedHashSet<>(parser.getConfigurationClasses());
        configClasses.removeAll(alreadyParsed);

        // Read the model and create bean definitions based on its content
        if (this.reader == null) {
            this.reader = new ConfigurationClassBeanDefinitionReader(
                    registry, this.sourceExtractor, this.resourceLoader, this.environment,
                    this.importBeanNameGenerator, parser.getImportRegistry());
        }
        this.reader.loadBeanDefinitions(configClasses);
        alreadyParsed.addAll(configClasses);

        candidates.clear();
        if (registry.getBeanDefinitionCount() > candidateNames.length) {
            String[] newCandidateNames = registry.getBeanDefinitionNames();
            Set<String> oldCandidateNames = new HashSet<>(Arrays.asList(candidateNames));
            Set<String> alreadyParsedClasses = new HashSet<>();
            for (ConfigurationClass configurationClass : alreadyParsed) {
                alreadyParsedClasses.add(configurationClass.getMetadata().getClassName());
            }
            for (String candidateName : newCandidateNames) {
                if (!oldCandidateNames.contains(candidateName)) {
                    BeanDefinition bd = registry.getBeanDefinition(candidateName);
                    if (ConfigurationClassUtils.checkConfigurationClassCandidate(bd, this.metadataReaderFactory) &&
                            !alreadyParsedClasses.contains(bd.getBeanClassName())) {
                        candidates.add(new BeanDefinitionHolder(bd, candidateName));
                    }
                }
            }
            candidateNames = newCandidateNames;
        }
    }
    while (!candidates.isEmpty());

    // Register the ImportRegistry as a bean in order to support ImportAware @Configuration classes
    if (sbr != null && !sbr.containsSingleton(IMPORT_REGISTRY_BEAN_NAME)) {
        sbr.registerSingleton(IMPORT_REGISTRY_BEAN_NAME, parser.getImportRegistry());
    }

    if (this.metadataReaderFactory instanceof CachingMetadataReaderFactory) {
        // Clear cache in externally provided MetadataReaderFactory; this is a no-op
        // for a shared cache since it'll be cleared by the ApplicationContext.
        ((CachingMetadataReaderFactory) this.metadataReaderFactory).clearCache();
    }
}

```

--------

<br>

### parse

下面详细的研究下parse的流程：

```java
public void parse(Set<BeanDefinitionHolder> configCandidates) {
    // 循环处理所有的候选者，如果是第一次的话，就只有我们的主类 AppTestApplication
    for (BeanDefinitionHolder holder : configCandidates) {
        BeanDefinition bd = holder.getBeanDefinition();
        // 找到合适的parse重载方法调用
        try {
            if (bd instanceof AnnotatedBeanDefinition) {
                // testApp 走的这个，之前创建的StandradAnnotatedBeanDefinition
                parse(((AnnotatedBeanDefinition) bd).getMetadata(), holder.getBeanName());
            }
            else if (bd instanceof AbstractBeanDefinition && ((AbstractBeanDefinition) bd).hasBeanClass()) {
                parse(((AbstractBeanDefinition) bd).getBeanClass(), holder.getBeanName());
            }
            else {
                parse(bd.getBeanClassName(), holder.getBeanName());
            }
        }
        catch (BeanDefinitionStoreException ex) {
            throw ex;
        }
        catch (Throwable ex) {
            throw new BeanDefinitionStoreException(
                    "Failed to parse configuration class [" + bd.getBeanClassName() + "]", ex);
        }
    }

    // 最后处理 需要被延迟处理的被 @Import 引入的类，这里常见的就是 AutoConfigurationImportSelector
    this.deferredImportSelectorHandler.process();
}

protected final void parse(AnnotationMetadata metadata, String beanName) throws IOException {
    // 构建为统一的 ConfigurationClass(用来描述配置类) 
    processConfigurationClass(new ConfigurationClass(metadata, beanName));
}

protected void processConfigurationClass(ConfigurationClass configClass) throws IOException {
    // 根据Conditional 是否需要 处理该配置类，关于Conditional 会单独详细分析
    if (this.conditionEvaluator.shouldSkip(configClass.getMetadata(), ConfigurationPhase.PARSE_CONFIGURATION)) {
        return;
    }

    // configurationClasses 成员变量 用来保存已经处理过的配置类，这里先看看之前处理过没
    ConfigurationClass existingClass = this.configurationClasses.get(configClass);
    if (existingClass != null) {
        if (configClass.isImported()) {
            if (existingClass.isImported()) {
                existingClass.mergeImportedBy(configClass);
            }
            // Otherwise ignore new imported config class; existing non-imported class overrides it.
            return;
        }
        else {
            // Explicit bean definition found, probably replacing an import.
            // Let's remove the old one and go with the new one.
            this.configurationClasses.remove(configClass);
            this.knownSuperclasses.values().removeIf(configClass::equals);
        }
    }

    // 开始处理
    // Recursively process the configuration class and its superclass hierarchy.
    // 递归找到真正的 SourceClass，找到 source 为class 的 而不是现在MetaData的SourceClass，同时这里还调用了 class上注解方法参数为 class类型的方法，并不知道有什么用
    SourceClass sourceClass = asSourceClass(configClass);
    // 如果被处理的ConfigClass有父类，那么他的父类也会被处理
    do {
        // 真正处理的方法，并且最后返回父类的SourceClass
        sourceClass = doProcessConfigurationClass(configClass, sourceClass);
    }
    while (sourceClass != null);

    // 放入 已处理的map中
    this.configurationClasses.put(configClass, configClass);
}

/**
 * Apply processing and build a complete {@link ConfigurationClass} by reading the
 * annotations, members and methods from the source class. This method can be called
 * multiple times as relevant sources are discovered.
 *
 * 该方法通过解析 该class，将class中的各种配置解析为ConfigurationClass中的各种属性，
 *
 */
@Nullable
protected final SourceClass doProcessConfigurationClass(ConfigurationClass configClass, SourceClass sourceClass)
        throws IOException {

    if (configClass.getMetadata().isAnnotated(Component.class.getName())) {
        // Recursively process any member (nested) classes first
        // 具体哪些数据会被当作member包装为SourceClass被处理，可以看Class.getDeclaredClasses方法
        processMemberClasses(configClass, sourceClass);
    }

    // Process any @PropertySource annotations
    // 这里可能可以配置多个@PropertySource
    // 每一次循环就是一个PropertySource，属性就是@PropertySource 里面声明的各个方法
    for (AnnotationAttributes propertySource : AnnotationConfigUtils.attributesForRepeatable(
            sourceClass.getMetadata(), PropertySources.class,
            org.springframework.context.annotation.PropertySource.class)) {
        // 如果Environment 是 可配置的话，将这个注解中引入的propertSource 添加到 env中
        // 该方法中 完成了解析 和 添加到env
        if (this.environment instanceof ConfigurableEnvironment) {
            processPropertySource(propertySource);
        }
        else {
            logger.info("Ignoring @PropertySource annotation on [" + sourceClass.getMetadata().getClassName() +
                    "]. Reason: Environment must implement ConfigurableEnvironment");
        }
    }

    // Process any @ComponentScan annotations
    // 拿到所有的@ComponentScan 中的键值对
    Set<AnnotationAttributes> componentScans = AnnotationConfigUtils.attributesForRepeatable(
            sourceClass.getMetadata(), ComponentScans.class, ComponentScan.class);
    
    if (!componentScans.isEmpty() &&
            !this.conditionEvaluator.shouldSkip(sourceClass.getMetadata(), ConfigurationPhase.REGISTER_BEAN)) {
        for (AnnotationAttributes componentScan : componentScans) {
            // The config class is annotated with @ComponentScan -> perform the scan immediately
            Set<BeanDefinitionHolder> scannedBeanDefinitions =
                    // 真正的parse是ClassPathBeanDefinitionScanner.doScann中执行的，
                    // 该方法中的parse 主要是 根据@ComponentScan 中的属性，构建用户真正解析的 ClassPathBeanDefinitionScanner
                    this.componentScanParser.parse(componentScan, sourceClass.getMetadata().getClassName());
            // Check the set of scanned definitions for any further config classes and parse recursively if needed
            // 这里扫描除了配置类(第一次到这儿的时候 就是我们的主类 AppTestApplication)中所有需要注入的BeanDefinition(这里就是工程里的service和controller了，还有其他我们自己配置的类)
            //  然后还需要继续扫描这些被注入的bean是不是配置类，如果是，还要把它当作配置再执行整个流程
            for (BeanDefinitionHolder holder : scannedBeanDefinitions) {
                BeanDefinition bdCand = holder.getBeanDefinition().getOriginatingBeanDefinition();
                if (bdCand == null) {
                    bdCand = holder.getBeanDefinition();
                }
                if (ConfigurationClassUtils.checkConfigurationClassCandidate(bdCand, this.metadataReaderFactory)) {
                    parse(bdCand.getBeanClassName(), holder.getBeanName());
                }
            }
        }
    }

    // Process any @Import annotations
    // getImprts 方法会拿到该类注解中所有引入类(SourceClass类型)(递归注解) 然后交由 processImports处理
    // 第一遍还是处理的主类，通常会拿到两个类
    //      1. org.springframework.boot.autoconfigure.AutoConfigurationPackages$Registrar
    //      2. org.springframework.boot.autoconfigure.AutoConfigurationImportSelector
    processImports(configClass, sourceClass, getImports(sourceClass), true);

    // Process any @ImportResource annotations
    AnnotationAttributes importResource =
            AnnotationConfigUtils.attributesFor(sourceClass.getMetadata(), ImportResource.class);
    if (importResource != null) {
        String[] resources = importResource.getStringArray("locations");
        Class<? extends BeanDefinitionReader> readerClass = importResource.getClass("reader");
        for (String resource : resources) {
            String resolvedResource = this.environment.resolveRequiredPlaceholders(resource);
            configClass.addImportedResource(resolvedResource, readerClass);
        }
    }

    // Process individual @Bean methods
    Set<MethodMetadata> beanMethods = retrieveBeanMethodMetadata(sourceClass);
    for (MethodMetadata methodMetadata : beanMethods) {
        configClass.addBeanMethod(new BeanMethod(methodMetadata, configClass));
    }

    // Process default methods on interfaces
    processInterfaces(configClass, sourceClass);

    // Process superclass, if any
    if (sourceClass.getMetadata().hasSuperClass()) {
        String superclass = sourceClass.getMetadata().getSuperClassName();
        if (superclass != null && !superclass.startsWith("java") &&
                !this.knownSuperclasses.containsKey(superclass)) {
            this.knownSuperclasses.put(superclass, configClass);
            // Superclass found, return its annotation metadata and recurse
            return sourceClass.getSuperClass();
        }
    }

    // No superclass -> processing is complete
    return null;
}

```

**`ClassPathBeanDefinitionScanner.doScann 根据@ComponentScan创建BeanDefinition的过程`**

```java

/**
    * Perform a scan within the specified base packages,
    * returning the registered bean definitions.
    * <p>This method does <i>not</i> register an annotation config processor
    * but rather leaves this up to the caller.
    * @param basePackages the packages to check for annotated classes
    * @return set of beans registered if any for tooling registration purposes (never {@code null})
    */
protected Set<BeanDefinitionHolder> doScan(String... basePackages) {
    Assert.notEmpty(basePackages, "At least one base package must be specified");
    Set<BeanDefinitionHolder> beanDefinitions = new LinkedHashSet<>();
    for (String basePackage : basePackages) {
        // 该方法 内部调用了 ClassPathScanningCandidateComponentProvider.scanCandidateComponents
        // ClassPathScanningCandidateComponentProvider 是 ClassPathBeanDefinitionScanner的父类
        Set<BeanDefinition> candidates = findCandidateComponents(basePackage);
        for (BeanDefinition candidate : candidates) {
            // 解析 Scope，不设置默认是Singleton。(Prototype每次创建一个实例)
            ScopeMetadata scopeMetadata = this.scopeMetadataResolver.resolveScopeMetadata(candidate);
            candidate.setScope(scopeMetadata.getScopeName());
            // BeanNameGenerator 老早就看到过了，终于在这里用来生成BeanName了
            String beanName = this.beanNameGenerator.generateBeanName(candidate, this.registry);
            if (candidate instanceof AbstractBeanDefinition) {
                // 完善BeanDefinition，这里设置了一些默认值
                postProcessBeanDefinition((AbstractBeanDefinition) candidate, beanName);
            }
            if (candidate instanceof AnnotatedBeanDefinition) {
                // 这里根据class上面的注解，比如@DependsOn,@Lazy设置相应的BeanDefinition的属性，下面贴出了源码
                AnnotationConfigUtils.processCommonDefinitionAnnotations((AnnotatedBeanDefinition) candidate);
            }
            if (checkCandidate(beanName, candidate)) {
                BeanDefinitionHolder definitionHolder = new BeanDefinitionHolder(candidate, beanName);
                definitionHolder =
                        AnnotationConfigUtils.applyScopedProxyMode(scopeMetadata, definitionHolder, this.registry);
                beanDefinitions.add(definitionHolder);
                // 最终注入到BeanFactory中
                registerBeanDefinition(definitionHolder, this.registry);
            }
        }
    }
    return beanDefinitions;
}



// ClassPathScanningCandidateComponentProvider.scanCandidateComponents
// 根据basePackage目录，扫描其中需要注入到spirng中的bean
private Set<BeanDefinition> scanCandidateComponents(String basePackage) {
    Set<BeanDefinition> candidates = new LinkedHashSet<>();
    try {
        // 构建被扫描的路径
        String packageSearchPath = ResourcePatternResolver.CLASSPATH_ALL_URL_PREFIX +
                resolveBasePackage(basePackage) + '/' + this.resourcePattern;
        // 拿到路径下 所有.class文件的 resource
        Resource[] resources = getResourcePatternResolver().getResources(packageSearchPath);
        boolean traceEnabled = logger.isTraceEnabled();
        boolean debugEnabled = logger.isDebugEnabled();
        for (Resource resource : resources) {
            if (traceEnabled) {
                logger.trace("Scanning " + resource);
            }
            if (resource.isReadable()) {
                try {
                    // 使用的CachingMetadataReaderFactory, 可以吧解析过的resource和其Metadata缓存起来
                    // 实际返回的是 SimpleMetadataReader 对象，在构造该对象的时候，完成了对资源的解析，和其中各种属性的读取
                    MetadataReader metadataReader = getMetadataReaderFactory().getMetadataReader(resource);
                    // 剩下的就是 根据meta信息 判断是否要注入，并添加到列表中
                    if (isCandidateComponent(metadataReader)) {
                        ScannedGenericBeanDefinition sbd = new ScannedGenericBeanDefinition(metadataReader);
                        sbd.setResource(resource);
                        sbd.setSource(resource);
                        if (isCandidateComponent(sbd)) {
                            if (debugEnabled) {
                                logger.debug("Identified candidate component class: " + resource);
                            }
                            candidates.add(sbd);
                        }
                        else {
                            if (debugEnabled) {
                                logger.debug("Ignored because not a concrete top-level class: " + resource);
                            }
                        }
                    ...
                    }}}}}   
}

// SimpleMetadataReader 对象的构建
SimpleMetadataReader(Resource resource, @Nullable ClassLoader classLoader) throws IOException {
    InputStream is = new BufferedInputStream(resource.getInputStream());
    ClassReader classReader;
    try {
        // ClassReader 是spring core 提供的用来解析class文件的类
        // 构造方法完成了 resource 的读取，将资源变成byte[]数组 存在成员变量中
        classReader = new ClassReader(is);
    }
    catch (IllegalArgumentException ex) {
        throw new NestedIOException("ASM ClassReader failed to parse class file - " +
                "probably due to a new Java class file version that isn't supported yet: " + resource, ex);
    }
    finally {
        is.close();
    }

    AnnotationMetadataReadingVisitor visitor = new AnnotationMetadataReadingVisitor(classLoader);
    // 吧class相关的metadata信息读取出来(根据class结构，偏移量一点点读取出来的)
    classReader.accept(visitor, ClassReader.SKIP_DEBUG);

    //  最后拿到了任何想拿到的信息
    this.annotationMetadata = visitor;
    // (since AnnotationMetadataReadingVisitor extends ClassMetadataReadingVisitor)
    this.classMetadata = visitor;
    this.resource = resource;
}

```


`AnnotationConfigUtils.processCommonDefinitionAnnotations 根据Bean的相关注解完善BeanDefinition的定义`
```java
static void processCommonDefinitionAnnotations(AnnotatedBeanDefinition abd, AnnotatedTypeMetadata metadata) {
    AnnotationAttributes lazy = attributesFor(metadata, Lazy.class);
    if (lazy != null) {
        abd.setLazyInit(lazy.getBoolean("value"));
    }
    else if (abd.getMetadata() != metadata) {
        lazy = attributesFor(abd.getMetadata(), Lazy.class);
        if (lazy != null) {
            abd.setLazyInit(lazy.getBoolean("value"));
        }
    }

    if (metadata.isAnnotated(Primary.class.getName())) {
        abd.setPrimary(true);
    }
    AnnotationAttributes dependsOn = attributesFor(metadata, DependsOn.class);
    if (dependsOn != null) {
        abd.setDependsOn(dependsOn.getStringArray("value"));
    }

    AnnotationAttributes role = attributesFor(metadata, Role.class);
    if (role != null) {
        abd.setRole(role.getNumber("value").intValue());
    }
    AnnotationAttributes description = attributesFor(metadata, Description.class);
    if (description != null) {
        abd.setDescription(description.getString("value"));
    }
}
```

---------------

<br>

### `@Import`注解的解析

```java
private void processImports(ConfigurationClass configClass, SourceClass currentSourceClass,
        Collection<SourceClass> importCandidates, boolean checkForCircularImports) {

    if (importCandidates.isEmpty()) {
        return;
    }

    if (checkForCircularImports && isChainedImportOnStack(configClass)) {
        this.problemReporter.error(new CircularImportProblem(configClass, this.importStack));
    }
    else {
        // 入栈，因为被Import的类，又引入了其他的类，然后其他的类 上面有使用@Import引入了其他类
        // 简单来说，springBoot就是在这里完成了 各种各样的自动装配
        // 主类 会通过@Import注解引入类 org.springframework.boot.autoconfigure.AutoConfigurationImportSelector
        // 然后该类会扫描 factories.properties 里面配置的所有 AutoConfiguration class，
        this.importStack.push(configClass);
        try {
            for (SourceClass candidate : importCandidates) {
                if (candidate.isAssignable(ImportSelector.class)) {
                    // Candidate class is an ImportSelector -> delegate to it to determine imports
                    // 被Import进来的是一个ImportSelector。 用来imports的
                    Class<?> candidateClass = candidate.loadClass();
                    ImportSelector selector = BeanUtils.instantiateClass(candidateClass, ImportSelector.class);
                    ParserStrategyUtils.invokeAwareMethods(
                            selector, this.environment, this.resourceLoader, this.registry);
                    // 拿到实例之后，如果该实例 是Defer(延迟)ImportSelector，添加到 延迟处理的list中 deferredImportSelectorHandler
                    if (selector instanceof DeferredImportSelector) {
                        this.deferredImportSelectorHandler.handle(
                                configClass, (DeferredImportSelector) selector);
                    }
                    else {
                        // 否则 直接处理，调用方法
                        String[] importClassNames = selector.selectImports(currentSourceClass.getMetadata());
                        Collection<SourceClass> importSourceClasses = asSourceClasses(importClassNames);
                        processImports(configClass, currentSourceClass, importSourceClasses, false);
                    }
                }
                else if (candidate.isAssignable(ImportBeanDefinitionRegistrar.class)) {
                    // Candidate class is an ImportBeanDefinitionRegistrar ->
                    // delegate to it to register additional bean definitions

                    // 被Import进来的是一个Registrar，用来注册其他的bean
                    Class<?> candidateClass = candidate.loadClass();
                    ImportBeanDefinitionRegistrar registrar =
                            BeanUtils.instantiateClass(candidateClass, ImportBeanDefinitionRegistrar.class);
                    ParserStrategyUtils.invokeAwareMethods(
                            registrar, this.environment, this.resourceLoader, this.registry);
                    // 实例化一个对象后，添加到 configClass的属性中
                    configClass.addImportBeanDefinitionRegistrar(registrar, currentSourceClass.getMetadata());
                }
                else {
                    // Candidate class not an ImportSelector or ImportBeanDefinitionRegistrar ->
                    // process it as an @Configuration class
                    this.importStack.registerImport(
                            currentSourceClass.getMetadata(), candidate.getMetadata().getClassName());
                    processConfigurationClass(candidate.asConfigClass(configClass));
                }
            }
        }
        catch (BeanDefinitionStoreException ex) {
            throw ex;
        }
        catch (Throwable ex) {
            throw new BeanDefinitionStoreException(
                    "Failed to process import candidates for configuration class [" +
                    configClass.getMetadata().getClassName() + "]", ex);
        }
        finally {
            this.importStack.pop();
        }
    }
}


```


`selector` 分为三种，

- 作为`ImportSelector`也就是`Importer`，用来引入其他类的。这种情况又做两种处理，延迟不延迟。
- 作为`ImportBeanDefinitionRegistrar`，通过import该类，来注册某些`Bean`
- 都不是的话，被当作`Configuration`配置类来处理

<br>

放在`deferredImportSelectorHandler`需要延迟处理的`selector`是在整个configClass解析完了之后才调用其中的方法的。

如果到这里解析完这个configClass，那么就会返回，如果它的父类为null，那么整个parse方法也会返回，最后调用deferprocess

```java
// 这是最开始的parse方法，最后调用了defer.process
public void parse(Set<BeanDefinitionHolder> configCandidates) {
    for (BeanDefinitionHolder holder : configCandidates) {
        BeanDefinition bd = holder.getBeanDefinition();
        try {
            if (bd instanceof AnnotatedBeanDefinition) {
                parse(((AnnotatedBeanDefinition) bd).getMetadata(), holder.getBeanName());
            }
            else if (bd instanceof AbstractBeanDefinition && ((AbstractBeanDefinition) bd).hasBeanClass()) {
                parse(((AbstractBeanDefinition) bd).getBeanClass(), holder.getBeanName());
            }
            else {
                parse(bd.getBeanClassName(), holder.getBeanName());
            }
        }
        catch (BeanDefinitionStoreException ex) {
            throw ex;
        }
        catch (Throwable ex) {
            throw new BeanDefinitionStoreException(
                    "Failed to parse configuration class [" + bd.getBeanClassName() + "]", ex);
        }
    }

    // 处理 DeferredImportSelector
    this.deferredImportSelectorHandler.process();
}
```

处理`AutoConfigurationImportSelector`

```java
public void process() {
    List<DeferredImportSelectorHolder> deferredImports = this.deferredImportSelectors;
    this.deferredImportSelectors = null;
    try {
        if (deferredImports != null) {
            // 将所有的DeferredImportSelector 包装为group
            DeferredImportSelectorGroupingHandler handler = new DeferredImportSelectorGroupingHandler();
            deferredImports.sort(DEFERRED_IMPORT_COMPARATOR);
            deferredImports.forEach(handler::register);
            // 处理imports
            handler.processGroupImports();
        }
    }
    finally {
        this.deferredImportSelectors = new ArrayList<>();
    }
}


public void processGroupImports() {
    for (DeferredImportSelectorGrouping grouping : this.groupings.values()) {
        // getImports 就已经扫描到了所有满足条件的注册的AutoConfiguration
        grouping.getImports().forEach(entry -> {
            ConfigurationClass configurationClass = this.configurationClasses.get(
                    entry.getMetadata());
            try {
                //把扫描出来的AutoConfiguration 都作为配置类 来处理。像之前处理主类 AppTestApplication 一样，
                processImports(configurationClass, asSourceClass(configurationClass),
                        asSourceClasses(entry.getImportClassName()), false);
            }
        ...
        });
    }
}

```

<br>

下面仔细看看 `getImports`方法

```java
public Iterable<Group.Entry> getImports() {
    for (DeferredImportSelectorHolder deferredImport : this.deferredImports) {
        this.group.process(deferredImport.getConfigurationClass().getMetadata(),
                deferredImport.getImportSelector());
    }
    // 拿到了经过初步筛选的AutoConfiguration之后，这一步是扫描各个AutoConfiguration中的exclude 属性，并排除
    // 最后该方法返回了 所有需要装配的配置类
    return this.group.selectImports();
}

// process 

public void process(AnnotationMetadata annotationMetadata,
        DeferredImportSelector deferredImportSelector) {
    // 扫描出所有的 EnableAutoConfiguration 并根据 扫描出来的AutoConfigurationMetaData 筛选满足条件的EnableAutoConfiguration
    AutoConfigurationEntry autoConfigurationEntry = ((AutoConfigurationImportSelector) deferredImportSelector)
            .getAutoConfigurationEntry(getAutoConfigurationMetadata(),
                    annotationMetadata);
    this.autoConfigurationEntries.add(autoConfigurationEntry);
    for (String importClassName : autoConfigurationEntry.getConfigurations()) {
        this.entries.putIfAbsent(importClassName, annotationMetadata);
    }
}

// 扫描 AutoConfiguration
protected AutoConfigurationEntry getAutoConfigurationEntry(
        AutoConfigurationMetadata autoConfigurationMetadata,
        AnnotationMetadata annotationMetadata) {
    if (!isEnabled(annotationMetadata)) {
        return EMPTY_ENTRY;
    }
    AnnotationAttributes attributes = getAttributes(annotationMetadata);
    // 获取到 所有 EnableAutoConfiguration 对应的 值
    List<String> configurations = getCandidateConfigurations(annotationMetadata,
            attributes);
    // 去重
    configurations = removeDuplicates(configurations);
    Set<String> exclusions = getExclusions(annotationMetadata, attributes);
    checkExcludedClasses(configurations, exclusions);
    // 去exclude exclude 是从configClass 也就是AppTestApplication 中的配置属性中获取的
    configurations.removeAll(exclusions);
    // 根据metadata 筛选出会被装配的Config
    configurations = filter(configurations, autoConfigurationMetadata);
    // report
    fireAutoConfigurationImportEvents(configurations, exclusions);
    return new AutoConfigurationEntry(configurations, exclusions);
}


// 看看如何获取

protected List<String> getCandidateConfigurations(AnnotationMetadata metadata,
        AnnotationAttributes attributes) {
    
    // getSpringFactoriesLoaderFactoryClass() 方法 就是直接返回这个类 EnableAutoConfiguration.class
    // SpringFactoriesLoader.loadFactoryNames 中使用的就是常量 FACTORIES_RESOURCE_LOCATION="META-INF/spring.factories"
    List<String> configurations = SpringFactoriesLoader.loadFactoryNames(
            getSpringFactoriesLoaderFactoryClass(), getBeanClassLoader());
    return configurations;
}


```

<br>

------------

<br>

### 流程总结

**看了这么多，`parse`的过程可能稍微有点蒙(博主自己至少跟了3遍源码)，那么最后捋一下整个流程**：

1. `parse`开始,也就是`processorConfigurationClass`，最开始默认的被解析类只有我们的启动配置类`AppTestApplication`
    1. 先看是否跳过`shuoldSkip`，然后包装`AppTestApplication`为`SourceClass`和`ConfigClass`（这两个类贯穿了整个AutoConfig流程）
    2. 然后真正进入解析--`doProcessConfigurationClass`。这里需要注意该方法返回的还是一个`SourceClass`对象，就是当前`ConfigClass`包装的类的父类。
        1. 解析注解`@Component, @PropertySources`
        2. 解析注解`@ComponentScans`，这时候拿到了我们工程中配置的，被这些注解`@Configuration, @Controller, @Service`修饰的类。
           1. 对这些类执行`parse`
        3. 解析注解`@Import` 这里需要检查循环import的问题
           1. 拿到当前配置类上所有`@Import`引入的类，包括注解类上的注解引入的。
           2. `processImports`. 被Import进来的一共分为三种：
              1. 作为`ImportSelector`也就是`Importer`，用来引入其他类的。这种情况又做两种处理，延迟不延迟。
                 1. 是`DeferredImportSelector`的子类(`AutoConfigurationImportSelector`就是它的字类)，放到`deferredHandler`延迟处理
                 2. 直接扫描该类上的`@Import`，并执行`processImport`
              2. 作为`ImportBeanDefinitionRegistrar`，通过import该类，来注册某些`Bean`
              3. 都不是的话，被当作`Configuration`配置类来处理，回到了最初的`processorConfigurationClass`
        4. 解析注解`@ImportResource, @Bean`等其他的。。。
    3. `doProcessConfigurationClass`返回`ConfigClass`包装的类的父类，继续`doProcessConfigurationClass`
2. 当前类的`parse`的最后，就是执行完`processorConfigurationClass`回来之后，再去处理之前放在`deferredHandler`中需要延迟处理的`ImportSelector`.`deferredImportSelectorHandler.process()`
   1. 处理`DeferredImports`，获取该`Import`想要import的类的列表。（`AutoConfigurationImportSelector`引入了一大堆配置类）
   2. 对这些配置类执行`processImports`。


------------

<br>

## 自动装配之条件装配


### Condition

`@Conditional`是Spring提供的核心注解之一，通常可以加在类或方法上，配合`@Configuration`和`@Bean`使用，当和`@Configuration`配合使用时，那么该类下所有`@Bean`方法 或者`@Import` 或者 `@ComponentScan`都会受到其配置条件的影响

`@Conditional`

```java
@Target({ElementType.TYPE, ElementType.METHOD})
@Retention(RetentionPolicy.RUNTIME)
@Documented
public @interface Conditional {

	/**
	 * All {@link Condition Conditions} that must {@linkplain Condition#matches match}
	 * in order for the component to be registered.
	 */
	Class<? extends Condition>[] value();

}
```

这个注解只有一个属性，值是`Condition`类型的。那么再看看`Condition`

<br>

`Condition`

```java
@FunctionalInterface
public interface Condition {

	/**
	 * Determine if the condition matches.
	 * @param context the condition context
	 * @param metadata metadata of the {@link org.springframework.core.type.AnnotationMetadata class}
	 * or {@link org.springframework.core.type.MethodMetadata method} being checked
	 * @return {@code true} if the condition matches and the component can be registered,
	 * or {@code false} to veto the annotated component's registration
	 */
	boolean matches(ConditionContext context, AnnotatedTypeMetadata metadata);

}
```

`Condition`是真正检测、匹配被`@Conditional`注解的类是否满足`@Conditional`中value属性配置的`Condition`中的条件。

简单来说，就是 `@Conditional`来引入条件判断的裁判`Condition`，真正判断是否match，就看`Condition`了。

<br>

`match`方法中有两个重要的参数，`ConditionContext context`能够帮忙获取spring中所有重要的环境变量，比如`BeanFactory, ResourceLoader, Environment`等, `AnnotatedTypeMetadata metadata`是获取被注解类上注解信息的。

<br><br>

`ConfigurationCondition`和`SpringBootCondition`都是`Conditon`的子类，也是Condition系列中比较重要的两个类。

`ConfigurationCondition`提供了更加灵活的控制，它多添加了一个用于设置解析Condition阶段的方法，在这里有两个阶段进行解析：

1. PARSE_CONFIGURATION：会在解析@Configuration时进行condition的过滤
2. REGISTER_BEAN：会在注册Bean的时候进行condition的过滤

<br>

`SpringBootCondition` 实现了`Condition` 而且SpringBoot中，很多Condition都继承子该类。

我们在自己写`Condition`的时候，实现哪个接口都可以。


那么我们常用的有`ConditionalOnClass,ConditionalOnMissingClass,ConditionalOnBean,ConditionalOnMissingBean`等等，比如还有以property作为条件，resource和profile作为条件的。

> `ConditionalOnBen`在使用的时候，需要注意装配顺序的问题， 可能因为装配顺序的原因，达不到预期的效果.

·


`ConfigurationClassBeanDefinitionReader`读取启动类上各种配置类中声明需要加载的bean
`ConfigurationClassPostProcessor` 就是读取自动配置引入类的processor

`ConfigurationClassParser.doProcessConfigurationClass` 真正解析`@Configuration`注解的类上的各种其他标签。
`ComponentScanAnnotationParser.parse` 真正解析 `@ComponentScan`注解标记需要扫描的类

spring 通过类`ClassReader`来解析.class文件，最后获取class的各种信息，包括Annotation信息(可是为什么不根据classLoader去获取该class的各种信息呢)。可以看看`SimpleMetadataReader`

------------

<br>

### spring-autoconfigure-metadata.properties

之前分析源码的时候，在过滤从`spring.factories`读取的所有`EnableAutoConfiguration`需要用到`AutoConfigurationMetadata`，是通过`AutoConfigurationImportSelector.getAutoConfigurationMetadata`来获取的：

```java
private AutoConfigurationMetadata getAutoConfigurationMetadata() {
    if (this.autoConfigurationMetadata == null) {
        this.autoConfigurationMetadata = AutoConfigurationMetadataLoader
                .loadMetadata(this.beanClassLoader);
    }
    return this.autoConfigurationMetadata;
}           

public static AutoConfigurationMetadata loadMetadata(ClassLoader classLoader) {
    // protected static final String PATH = "META-INF/spring-autoconfigure-metadata.properties"
    return loadMetadata(classLoader, PATH);
}

```

`AutoConfigurationMetadata`就是从`META-INF/spring-autoconfigure-metadata.properties`读取的。

怎么使用呢？比如说`spring.factories`中配置了

```properties
org.springframework.boot.autoconfigure.EnableAutoConfiguration=\
  com.ys.zhshop.member.config.MemberAutoConfiguration
```

`spring-autoconfigure-metadata.properties`配置了

```properties
com.ys.zhshop.member.config.MemberAutoConfiguration.ConditionalOnClass=java.lang.String
```

基本格式就是**`自动配置的类全名.条件=值`**，上面条件满足了，所以就会加在这个配置类。

- [更多关于@Conditional](https://www.cnblogs.com/niechen/p/9047264.html#_labelTop)
- [更多关于spring-autoconfigure-metadata.properties](https://yq.aliyun.com/articles/617718)


[理解和使用@Import](https://blog.csdn.net/tuoni123/article/details/80213050)

[使用自动装配的例子-EnableConfigurationProperities](https://blog.csdn.net/zknxx/article/details/79183698)






