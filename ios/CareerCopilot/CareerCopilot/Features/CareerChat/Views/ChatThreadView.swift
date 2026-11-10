import SwiftUI

struct ChatThreadView: View {
    @ObservedObject var model: ChatViewModel
    let conversation: ChatConversation
    @FocusState private var composerFocused: Bool
    @State private var confirmAnswer = false
    @State private var pendingQuestionID: UUID?
    @State private var retrying = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "sparkles").foregroundStyle(ChatStyle.cyan)
                            .frame(width: 40, height: 40).background(ChatStyle.surface, in: Circle())
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Your career chat").font(.headline).foregroundStyle(.white)
                            Text("Ask a career question. Answers use a small set of project-authored guidance and include sources when available.").font(.subheadline).foregroundStyle(ChatStyle.muted)
                        }
                        .padding(16).background(ChatStyle.surface, in: RoundedRectangle(cornerRadius: 20))
                    }
                    if model.isLoading { ProgressView("Loading messages").tint(.white).foregroundStyle(ChatStyle.muted) }
                    if model.hasLoadedMessages && model.messages.isEmpty && !model.isLoading && model.draft.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Not sure where to start?").font(.headline).foregroundStyle(.white)
                            Text("Choose a question or write your own below.").font(.subheadline).foregroundStyle(ChatStyle.muted)
                            ForEach(["How can I prepare for an interview?", "How can I improve my resume?", "How should I approach a career change?"], id: \.self) { suggestion in
                                Button {
                                    model.draft = suggestion
                                    composerFocused = true
                                } label: {
                                    HStack {
                                        Text(suggestion).multilineTextAlignment(.leading)
                                        Spacer()
                                        Image(systemName: "arrow.up.left")
                                    }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).padding(.horizontal, 14)
                                }
                                .buttonStyle(.plain).foregroundStyle(.white)
                                .background(ChatStyle.surface, in: RoundedRectangle(cornerRadius: 14))
                                .accessibilityHint("Adds this question to the message field for you to review.")
                            }
                        }
                    }
                    if let error = model.error {
                        VStack(alignment: .leading, spacing: 8) {
                            Label(error, systemImage: "exclamationmark.circle").foregroundStyle(.white)
                            Button("Refresh messages") { Task { await model.loadMessages(conversationID: conversation.id) } }.foregroundStyle(ChatStyle.cyan).frame(minHeight: 44)
                        }.padding(14).background(ChatStyle.surface, in: RoundedRectangle(cornerRadius: 16))
                    }
                    ForEach(model.messages) { message in
                        HStack(alignment: .bottom) {
                            if message.role == .user { Spacer(minLength: 40) }
                            VStack(alignment: .leading, spacing: 10) {
                                Text(message.content).foregroundStyle(.white).textSelection(.enabled)
                                    .accessibilityLabel("\(message.role == .user ? "You" : "Assistant"): \(message.content)")
                                if let citations = message.citations, !citations.isEmpty {
                                    Text("Sources").font(.caption.bold()).foregroundStyle(ChatStyle.muted)
                                    ForEach(citations) { citation in
                                        DisclosureGroup(citation.title) {
                                            VStack(alignment: .leading, spacing: 6) {
                                                Text(citation.origin).font(.caption).foregroundStyle(ChatStyle.muted)
                                                Text(citation.excerpt).font(.footnote).foregroundStyle(.white).textSelection(.enabled)
                                            }.padding(.top, 4)
                                        }.font(.subheadline).foregroundStyle(.white).tint(ChatStyle.cyan)
                                    }
                                }
                                if message.role == .user && !model.hasAnswer(for: message.id) {
                                    Button("Get answer") { pendingQuestionID = message.id; retrying = false; confirmAnswer = true }
                                        .font(.caption.weight(.semibold)).foregroundStyle(ChatStyle.cyan)
                                        .frame(minHeight: 44)
                                        .accessibilityHint("Requests an answer to this question.")
                                        .disabled(model.isRequestingAnswer || model.answerJob?.status == .queued || model.answerJob?.status == .running)
                                }
                            }
                            .padding(15)
                            .background(message.role == .user ? Color(red: 0.04, green: 0.32, blue: 0.46) : ChatStyle.surface, in: RoundedRectangle(cornerRadius: 20))
                            if message.role == .assistant { Spacer(minLength: 40) }
                        }.id(message.id)
                    }
                    if model.hasMoreMessages {
                        Button("Load more messages") { Task { await model.loadMessages(conversationID: conversation.id, reset: false) } }
                            .foregroundStyle(ChatStyle.cyan)
                            .frame(minHeight: 44)
                        Text("Load all messages before adding a new one.").font(.caption).foregroundStyle(ChatStyle.muted)
                    }
                    if model.isRequestingAnswer {
                        ProgressView("Requesting an answer").tint(.white).foregroundStyle(ChatStyle.muted)
                    } else if let job = model.answerJob, job.status == .queued || job.status == .running, !model.answerPollingPaused {
                        ProgressView(LocalizedStringKey(job.status == .running ? "Preparing an answer" : "Waiting for an answer")).tint(.white).foregroundStyle(ChatStyle.muted)
                    }
                    if let answerError = model.answerError {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(answerError).foregroundStyle(.white)
                            if model.answerPollingPaused {
                                Button("Check status") { model.checkAnswerStatus() }.foregroundStyle(ChatStyle.cyan).frame(minHeight: 44)
                            } else if model.answerJob?.status == .failed {
                                Button("Retry answer") { retrying = true; confirmAnswer = true }.foregroundStyle(ChatStyle.cyan).frame(minHeight: 44)
                            }
                        }.padding(14).background(ChatStyle.surface, in: RoundedRectangle(cornerRadius: 16))
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .frame(maxWidth: 700, alignment: .leading).frame(maxWidth: .infinity).padding(20)
            }
            .onChange(of: model.messages.count) { _, _ in
                withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
            }
        }
        .background(ChatStyle.gradient.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) { composer }
        .navigationTitle(conversation.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .tint(ChatStyle.cyan)
        .task { await model.open(conversation) }
        .task(id: model.answerPollingToken) { await model.pollAnswer(conversationID: conversation.id) }
        .onDisappear { model.close(conversationID: conversation.id) }
        .confirmationDialog("Send this question for an answer?", isPresented: $confirmAnswer, titleVisibility: .visible) {
            Button("Send for an answer") {
                let questionID = pendingQuestionID
                let shouldRetry = retrying
                pendingQuestionID = nil
                retrying = false
                Task {
                    if shouldRetry { await model.retryAnswer(conversationID: conversation.id) }
                    else if let questionID { await model.requestAnswer(conversationID: conversation.id, questionID: questionID) }
                    else if let message = await model.send(conversationID: conversation.id) {
                        await model.requestAnswer(conversationID: conversation.id, questionID: message.id)
                    }
                }
            }
            Button("Cancel", role: .cancel) { pendingQuestionID = nil; retrying = false }
        } message: {
            Text("Your question and retrieved guidance may be sent to OpenRouter and Google Gemini, or processed by local Ollama. Google’s free tier may use content to improve its products. Use synthetic data until privacy is reviewed.")
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom, spacing: 10) {
                TextField("Write a career question", text: $model.draft, prompt: Text("Write a career question").foregroundStyle(ChatStyle.muted), axis: .vertical)
                    .lineLimit(1...5)
                    .focused($composerFocused)
                    .foregroundStyle(.white)
                    .tint(ChatStyle.cyan)
                    .accessibilityLabel("Career question")
                    .padding(14)
                    .background(ChatStyle.surface, in: RoundedRectangle(cornerRadius: 22))
                Button {
                    pendingQuestionID = nil
                    retrying = false
                    confirmAnswer = true
                } label: {
                    if model.isSending { ProgressView().tint(.black).frame(width: 48, height: 48) }
                    else { Image(systemName: "arrow.up").font(.headline).frame(width: 48, height: 48) }
                }
                .accessibilityLabel("Send question")
                .accessibilityHint("Shows a confirmation before sending your question for an answer.")
                .foregroundStyle(.black)
                .background(ChatStyle.cyan, in: Circle())
                .disabled(!canSend)
                .opacity(canSend ? 1 : 0.45)
            }
            Text(composerStatus)
                .font(.caption).foregroundStyle(ChatStyle.muted)
        }
        .frame(maxWidth: 700).frame(maxWidth: .infinity)
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(ChatStyle.background)
    }

    private var canSend: Bool {
        !model.isSending && !model.isLoading && !model.isRequestingAnswer &&
        model.answerJob?.status != .queued && model.answerJob?.status != .running &&
        model.hasLoadedMessages && !model.hasMoreMessages && !model.needsRefreshBeforeSending &&
        !model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && model.draft.unicodeScalars.count <= 4000
    }

    private var composerStatus: String {
        let count = model.draft.unicodeScalars.count
        if count > 4000 { return "Your question is too long. \(count) of 4000 characters." }
        if !model.hasLoadedMessages { return "Load messages before sending a question." }
        if model.needsRefreshBeforeSending { return "Refresh messages before sending again." }
        if model.hasMoreMessages { return "Load all messages before sending a question." }
        if model.isRequestingAnswer || model.answerJob?.status == .queued || model.answerJob?.status == .running {
            return "Wait for the current answer. \(count) of 4000 characters."
        }
        return "Review AI answers and their sources. \(count) of 4000 characters."
    }
}

#Preview("Conversation") {
    NavigationStack {
        ChatThreadView(model: ChatViewModel(clientFactory: { _ in ChatPreviewService() }), conversation: ChatConversation(id: UUID(), title: "Career goals", createdAt: "", updatedAt: ""))
    }
}

#Preview("Conversation · large text") {
    NavigationStack {
        ChatThreadView(model: ChatViewModel(clientFactory: { _ in ChatPreviewService() }), conversation: ChatConversation(id: UUID(), title: "Career goals", createdAt: "", updatedAt: ""))
    }
    .environment(\.dynamicTypeSize, .accessibility3)
}
