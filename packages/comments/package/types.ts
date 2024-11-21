import { AbiParameterToPrimitiveType, ExtractAbiFunction } from "abitype";
import { commentsImplABI } from "./wagmiGenerated";
export type CommentIdentifier = AbiParameterToPrimitiveType<
  ExtractAbiFunction<
    typeof commentsImplABI,
    "hashCommentIdentifier"
  >["inputs"][0]
>;
