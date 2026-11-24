import Foundation
import KilnCore
import Observation

/// The 3D screen's state: the picture and settings being edited, what a running
/// generation is doing, and the object on the stage.
@MainActor
@Observable
final class ObjectsStore {
    var draft = MeshDraft()
    private(set) var activity = Activity.idle
    /// When the running generation started, for showing how long it has taken.
    private(set) var startedAt: Date?
    /// The picture the running generation is working from.
    private(set) var workingPicture: URL?
    /// A picture drawn from a description, waiting to be approved before it is made into an object.
    private(set) var proposal: GalleryItem?
    /// The image model that draws pictures from descriptions. Nil uses the first one installed.
    var pictureRecipeID: String?
    /// True while the stage shows what is being made, or the picture waiting to be approved,
    /// and not an earlier object. Looking at another object leaves the work running.
    private(set) var watchesWork = false
    /// An object finished while another was being looked at, until it is opened.
    private(set) var unseenID: UUID?
    /// The object on the stage.
    private(set) var current: MeshItem?
    var errorMessage: String?
    /// True while another screen is using the engine. Only one model runs at a time.
    var isEngineBusyElsewhere: () -> Bool = { false }

    let library: ModelLibrary
    let objects: MeshLibrary
    private let gallery: GalleryLibrary
    private let attachments: AttachmentLibrary
    private let engine: any InferenceEngine
    private var task: Task<Void, Never>?

    init(
        library: ModelLibrary, objects: MeshLibrary, gallery: GalleryLibrary, attachments: AttachmentLibrary,
        engine: any InferenceEngine
    ) {
        self.library = library
        self.objects = objects
        self.gallery = gallery
        self.attachments = attachments
        self.engine = engine
        current = objects.items.first
        selectDefaultRecipeIfNeeded()
    }

    // MARK: - Picture

    /// Takes a picture to make an object from. It is copied, so the object can
    /// be made again after the original is moved or deleted.
    func setPicture(_ file: URL) {
        do {
            draft.image = try attachments.add(file, accepting: [.image])
            proposal = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: - Generating

    var isGenerating: Bool { activity != .idle }

    /// What sending would do next: draw a picture, or make the object.
    var nextStep: MeshDraft.Step? {
        draft.nextStep(objectRecipe: selectedRecipe, imageRecipe: pictureRecipe)
    }

    var canGenerate: Bool {
        !isGenerating && !isEngineBusyElsewhere() && nextStep != nil
    }

    /// Sends the composer: a picture is made into an object; a description is drawn first.
    func generate() {
        guard canGenerate else { return }
        if nextStep == .picture { drawPicture() } else { makeObject() }
    }

    private func makeObject() {
        guard let recipe = selectedRecipe else { return }
        if draft.randomSeed {
            draft.seed = GenerationRequest.randomSeed()
        }
        guard let request = draft.request, let picture = draft.image else { return }
        // The composer empties, as on the other screens; the stage shows what is being worked on.
        workingPicture = picture
        watchesWork = true
        draft.image = nil
        draft.prompt = ""
        proposal = nil
        errorMessage = nil
        activity = .starting
        let started = Date()
        startedAt = started
        task = Task {
            do {
                for try await event in engine.generate(recipe: recipe, request: request) {
                    switch event {
                    case .loadingModel, .preview, .segment: break
                    case .progress(let progress): activity = .building(progress)
                    case .finished(.mesh(let mesh)):
                        let record = GenerationRecord(
                            recipeID: recipe.id, recipeName: recipe.name, request: request,
                            durationSeconds: Date().timeIntervalSince(started)
                        )
                        let made = try objects.add(mesh, record: record)
                        // Someone looking at another object is not pulled away from it.
                        if watchesWork || current == nil { current = made } else { unseenID = made.id }
                    case .finished:
                        errorMessage = "The model did not produce a 3D object."
                    }
                }
                if current?.record.request != request { restore(picture) }
            } catch is CancellationError {
                restore(picture)
            } catch {
                restore(picture)
                errorMessage = GenerationFailure.message(for: error, recipe: recipe)
            }
            activity = .idle
            startedAt = nil
            workingPicture = nil
        }
    }

    /// Draws a picture of what is described and holds it up for approval.
    private func drawPicture() {
        guard let recipe = pictureRecipe, let request = draft.pictureRequest(for: recipe, seed: GenerationRequest.randomSeed()) else { return }
        errorMessage = nil
        proposal = nil
        watchesWork = true
        activity = .picturing(nil)
        let started = Date()
        startedAt = started
        task = Task {
            do {
                for try await event in engine.generate(recipe: recipe, request: request) {
                    switch event {
                    case .loadingModel, .preview, .segment: break
                    case .progress(let progress): activity = .picturing(progress)
                    case .finished(.image(let image)):
                        let record = GenerationRecord(
                            recipeID: recipe.id, recipeName: recipe.name, request: request,
                            durationSeconds: Date().timeIntervalSince(started)
                        )
                        proposal = try gallery.add(image, record: record)
                    case .finished:
                        errorMessage = "The model did not produce a picture."
                    }
                }
            } catch is CancellationError {
                // Stopped by the user: the description is still in the composer.
            } catch {
                errorMessage = GenerationFailure.message(for: error, recipe: recipe)
            }
            activity = .idle
            startedAt = nil
        }
    }

    /// Makes the object from the picture that was drawn.
    func acceptProposal() {
        guard let proposal, !isGenerating else { return }
        setPicture(proposal.url)
        if draft.image != nil { generate() }
    }

    /// Draws another picture from the same description.
    func redrawProposal() {
        guard !isGenerating else { return }
        proposal = nil
        if nextStep == .picture { generate() }
    }

    func dismissProposal() {
        proposal = nil
    }

    /// Puts what is being made, or the picture waiting for approval, back on the stage.
    func watchWork() {
        watchesWork = true
    }

    func cancel() {
        task?.cancel()
    }

    /// Puts a picture that produced no object back in the composer, unless another was chosen meanwhile.
    private func restore(_ picture: URL) {
        if draft.image == nil { draft.image = picture }
    }

    // MARK: - Objects

    func show(_ item: MeshItem) {
        current = item
        watchesWork = false
        if unseenID == item.id { unseenID = nil }
    }

    /// Puts back the picture and settings an object was made with.
    func reuse(_ item: MeshItem) {
        draft.reuse(item.record.request)
        // After the settings, so a level of detail the model in use lacks is not kept.
        selectRecipe(recipes.first { $0.id == item.record.recipeID } ?? selectedRecipe)
    }

    func delete(_ item: MeshItem) {
        do {
            try objects.delete(item)
            if current?.id == item.id {
                current = objects.items.first
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    #if DEBUG
    /// Shows the screen as it is while an object is being made, for snapshots.
    func loadPreview(activity: Activity, picture: URL?) {
        self.activity = activity
        watchesWork = !CommandLine.arguments.contains("--browse-while-building")
        if case .picturing = activity { draft.prompt = "A brass pocket watch" }
        startedAt = Date().addingTimeInterval(-74)
        workingPicture = picture
    }
    #endif
}
